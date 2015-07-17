require 'protobuf/rpc/server'

# RSpec Helpers designed to give you mock abstraction of client or service layer.
# Require as protobuf/rspec/helpers and include into your running RSpec configuration.
#
# @example Configure RSpec to use Protobuf Helpers
#     require 'protobuf/rspec'
#     RSpec.configure do |config|
#       config.include Protobuf::Rspec::Helpers
#     end
#
module Protobuf
  module RSpec
    module Helpers

      def self.included(other)
        other.class_eval do
          extend ::Protobuf::RSpec::Helpers::ClassMethods
          include ::Protobuf::RSpec::Helpers::InstanceMethods
        end
      end

      module ClassMethods

        # Set the service subject. Use this method when the described_class is
        # not the class you wish to use with methods like local_rpc,
        # request_class, or response_class.
        #
        # @example Override subject service for local_rpc calls
        #     describe Foo::BarService do
        #       # Use Foo::BazService instead of Foo::BarService
        #       subject_service { Foo::BazService }
        #
        #       subject { local_rpc(:find, request) }
        #       its('response.records') { should have(3).items }
        #     end
        #
        def subject_service
          if block_given?
            @_subject_service = yield
          else
            defined?(@_subject_service) ? @_subject_service : described_class
          end
        end

      end

      module InstanceMethods

        def subject_service
          self.class.subject_service
        end

        # Call a local RPC service to test responses and behavior based on the
        # given request (without testing the underlying socket implementation).
        #
        # @example Test a local service method
        #     # Implementation
        #     module Services
        #       class UserService < Protobuf::Rpc::Service
        #         def create
        #           if request.name
        #             user = User.create_from_proto(request)
        #             respond_with(user)
        #           else
        #             rpc_failed 'Error: name required'
        #           end
        #         end
        #
        #         def notify
        #           user = User.find_by_guid(request.guid)
        #           if user
        #             Resque.enqueue(EmailUserJob, user.id)
        #             respond_with(:queued => true)
        #           else
        #             rpc_failed 'Error: user not found'
        #           end
        #         end
        #       end
        #     end
        #
        #     # Spec
        #     describe Services::UserService do
        #       describe '#create' do
        #         subject { local_rpc(:create, request) }
        #
        #         context 'when request is valid' do
        #           let(:request) { { :name => 'Jack' } }
        #           let(:user_mock) { FactoryGirl.build(:user) }
        #           before { User.should_receive(:create_from_proto).and_return(user_mock) }
        #           it { should eq(user_mock) }
        #         end
        #
        #         context 'when name is not given' do
        #           let(:request) { :name => '' }
        #           it { should =~ /Error/ }
        #         end
        #       end
        #
        #       describe '#notify' do
        #         let(:request) { { :guid => 'USR-123' } }
        #         let(:user_mock) { FactoryGirl.build(:user) }
        #         subject { local_rpc(:notify, request) }
        #
        #         context 'when user is found' do
        #           before { User.should_receive(:find_by_guid).with(request.guid).and_return(user_mock) }
        #           before { Resqueue.should_receive(:enqueue).with(EmailUserJob, request.guid)
        #           its(:queued) { should be_true }
        #         end
        #
        #         context 'when user is not found' do
        #           before { Resque.should_not_receive(:enqueue) }
        #           it { should =~ /Error/ }
        #         end
        #       end
        #     end
        #
        # @param [Symbol, String] method a symbol or string denoting the method to call.
        # @param [Protobuf::Message or Hash] request the request message of the expected type for the given method.
        # @return [Protobuf::Message or String] the resulting protobuf message or error string
        #
        def local_rpc(rpc_method, request)
          env = rpc_env(rpc_method, request)
          service = subject_service.new(env)

          yield(service) if block_given?

          # Dispatch the RPC method invoking all of the filters
          service.callable_rpc_method(rpc_method).call
          service.response
        end

        # Make an RPC call invoking the entire middleware stack (without testing
        # the underlying socket implementation). Works the same as `local_rpc`, but
        # invokes the entire RPC middleware stack.
        #
        # @example Test an RPC method
        #
        #     it "returns a user" do
        #       response = rpc(:find, request)
        #       response.should eq user
        #     end
        #
        # @param [Symbol, String] method a symbol or string denoting the method to call.
        # @param [Protobuf::Message or Hash] request the request message of the expected type for the given method.
        # @return [Protobuf::Message or Protobuf::Rpc::PbError] the resulting Protobuf message or RPC error.
        #
        def rpc(rpc_method, request)
          request_wrapper = wrapped_request(rpc_method, request)

          env = ::Protobuf::Rpc::Env.new('encoded_request' => request_wrapper.encode)
          env = ::Protobuf::Rpc.middleware.call(env)

          env.response
        end

        # Initialize a new RPC env object simulating what happens in the middleware stack.
        # Useful for testing a service class directly without using `rpc` or `local_rpc`.
        #
        # @example Test an RPC method on the service directly
        #
        #     describe "#create" do
        #       # Initialize request and response
        #       # ...
        #       let(:env) { rpc_env(:create, request) }
        #
        #       subject { described_class.new(env) }
        #
        #       it "creates a user" do
        #         subject.create
        #         subject.response.should eq response
        #       end
        #     end
        #
        # @param [Symbol, String] method a symbol or string denoting the method to call.
        # @param [Protobuf::Message or Hash] request the request message of the expected type for the given method.
        # @return [Protobuf::Rpc::Env] the environment derived from an RPC request.
        #
        def rpc_env(rpc_method, request)
          request = request_class(rpc_method).new(request) if request.is_a?(Hash)

          ::Protobuf::Rpc::Env.new(
            'caller'          => 'protobuf-rspec',
            'service_name'    => subject_service.to_s,
            'method_name'     => rpc_method.to_s,
            'request'         => request,
            'request_type'    => request_class(rpc_method),
            'response_type'   => response_class(rpc_method),
            'rpc_method'      => subject_service.rpcs[rpc_method],
            'rpc_service'     => subject_service
          )
        end
        alias_method :env_for_request, :rpc_env

        # Create a mock service that responds in the way you are expecting to aid in testing client -> service calls.
        # In order to test your success callback you should provide a :response object. Similarly, to test your failure
        # callback you should provide an :error object.
        #
        # Asserting the request object can be done one of two ways: direct or explicit. If you would like to directly test
        # the object that is given as a request you should provide a :request object as part of the cb_mocks third parameter hash.
        # Alternatively you can do an explicit assertion by providing a block to mock_rpc. The block will be yielded with
        # the request object as its only parameter. This allows you to perform your own assertions on the request object
        # (e.g. only check a few of the fields in the request). Also note that if a :request param is given in the third param,
        # the block will be ignored.
        #
        # @example Testing the client on_success callback
        #     # Method under test
        #     def create_user(request)
        #       status = 'unknown'
        #       Proto::UserService.client.create(request) do |c|
        #         c.on_success do |response|
        #           status = response.status
        #         end
        #       end
        #       status
        #     end
        #     ...
        #
        #     # spec
        #     it 'verifies the on_success method behaves correctly' do
        #       response_mock = mock('response_mock', :status => 'success')
        #       mock_rpc(Proto::UserService, :client, :response => response_mock)
        #       create_user(request).should eq('success')
        #     end
        #
        # @example Testing the client on_failure callback
        #     # Method under test
        #     def create_user(request)
        #       status = nil
        #       Proto::UserService.client.create(request) do |c|
        #         c.on_failure do |error|
        #           status = 'error'
        #           ErrorReporter.report(error.message)
        #         end
        #       end
        #       status
        #     end
        #     ...
        #
        #     # spec
        #     it 'verifies the on_success method behaves correctly' do
        #       error_mock = mock('error_mock', :message => 'this is an error message')
        #       mock_rpc(Proto::UserService, :client, :error => error_mock)
        #       ErrorReporter.should_receive(:report).with(error_mock.message)
        #       create_user(request).should eq('error')
        #     end
        #
        # @example Testing the given client request object (direct assert)
        #     # Method under test
        #     def create_user
        #       request = ... # some operation to build a request on state
        #       Proto::UserService.client.create(request) do |c|
        #         ...
        #       end
        #     end
        #     ...
        #
        #     # spec
        #     it 'verifies the request is built correctly' do
        #       expected_request = ... # some expectation
        #       mock_rpc(Proto::UserService, :client, :request => expected_request)
        #       create_user(request)
        #     end
        #
        # @example Testing the given client request object (block assert)
        #     # Method under test
        #     def create_user
        #       request = ... # some operation to build a request on state
        #       Proto::UserService.client.create(request) do |c|
        #         ...
        #       end
        #     end
        #     ...
        #
        #     # spec
        #     it 'verifies the request is built correctly' do
        #       mock_rpc(Proto::UserService, :client) do |given_request|
        #         given_request.field1.should eq 'rainbows'
        #         given_request.field2.should eq 'ponies'
        #       end
        #       create_user(request)
        #     end
        #
        # @param [Class] klass the service class constant
        # @param [Symbol, String] method a symbol or string denoting the method to call
        # @param [Hash] callbacks provides expectation objects to invoke on_success (with :response), on_failure (with :error), and the request object (:request)
        # @param [Block] optional. When given, will be invoked with the request message sent to the client method
        # @return [Mock] the stubbed out client mock
        #
        def mock_rpc(klass, method, callbacks = {})
          client = double('Client', :on_success => true, :on_failure => true)
          allow(client).to receive(method).and_yield(client)

          allow(klass).to receive(:client).and_return(client)

          case
          when callbacks[:request] then
            client.should_receive(method).with(callbacks[:request])
          when block_given? then
            client.should_receive(method) do |given_req|
              yield(given_req)
            end
          else
            client.should_receive(method)
          end

          success = callbacks[:success] || callbacks[:response]
          allow(client).to receive(:on_success).and_yield(success) unless success.nil?

          failure = callbacks[:failure] || callbacks[:error]
          allow(client).to receive(:on_failure).and_yield(failure) unless failure.nil?

          client
        end
        alias_method :mock_service, :mock_rpc
        alias_method :mock_remote_service, :mock_rpc

        # Returns the request class for a given endpoint of the described class
        #
        # @example
        #     # With a create endpoint that takes a UserRequest object:
        #     request_class(:create) # => UserRequest
        #
        def request_class(endpoint)
          subject_service.rpcs[endpoint].request_type
        end

        # Returns the response class for a given endpoint of the described class
        #
        # @example
        #     # With a create endpoint that takes a UserResponse object:
        #     response_class(:create) # => UserResponse
        #
        def response_class(endpoint)
          subject_service.rpcs[endpoint].response_type
        end

        # Returns the request wrapper that is encoded and sent over the wire when calling
        # an RPC method with the given request
        #
        # @param [Symbol, String] method a symbol or string denoting the method to call.
        # @param [Protobuf::Message or Hash] request the request message of the expected type for the given method.
        # @return [Protobuf::Socketrpc::Request] the wrapper used to transmit RPC requests.
        #
        def wrapped_request(rpc_method, request)
          request = request_class(rpc_method).new(request) if request.is_a?(Hash)

          ::Protobuf::Socketrpc::Request.new(
            :service_name => subject_service.to_s,
            :method_name => rpc_method.to_s,
            :request_proto => request.encode,
            :caller => 'protobuf-rspec'
          )
        end
      end
    end
  end
end
