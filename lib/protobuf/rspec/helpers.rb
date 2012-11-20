require 'protobuf/rpc/rpc.pb'

# RSpec Helpers designed to give you mock abstraction of client or service layer.
# Require as protobuf/rspec/helpers and include into your running RSpec configuration.
#
# @example Configure RSpec to use Protobuf Helpers
#     require 'protobuf/rspec'
#     RSpec.configure do |config|
#       config.include Protobuf::Rspec::Helpers
#     end
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
        # not the class you wish to use with methods like local_rpc. In t
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
        # @example Override subject service for remote_rpc mocks
        #     describe BarController do
        #       describe '#index' do
        #         subject_service { Foo::BarService }
        #         subject { remote_rpc(:find, request, response) }
        #       end
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

        # Call a local service to test responses and behavior based on the given request.
        # Should use to outside-in test a local RPC Service without testing the underlying socket implementation.
        #
        # @example Test a local service method
        #     # Implementation
        #     module Proto
        #       class UserService < Protobuf::Rpc::Service
        #         def create
        #           user = User.create_from_proto(request)
        #           if request.name
        #             respond_with(ProtoRepresenter.new(user))
        #           else
        #             rpc_failed 'Error: name required'
        #           end
        #         end
        #       end
        #     end
        #
        #     # Spec
        #     describe Proto::UserService do
        #       describe '#create' do
        #         it 'creates a new user' do
        #           create_request = Proto::UserCreate.new(...)
        #           service = call_local_service(Proto::UserService, :create, create_request)
        #           service.response.should eq(some_response_object)
        #         end
        #
        #         it 'fails when name is not given' do
        #           bad_req = { :name => nil }
        #           service = call_local_service(Proto::UserService, :create, :create_request) do |service|
        #             # Block is yielded before the method is invoked.
        #             service.should_receive(:rpc_failed).with('Error: name required')
        #           end
        #         end
        #       end
        #     end
        #
        # @param [Symbol, String] method a symbol or string denoting the method to call.
        # @param [Protobuf::Message or Hash] request the request message of the expected type for the given method.
        # @return [Protobuf::Message or String] the resulting protobuf message or error string
        def local_rpc(rpc_method, request)
          request = subject_service.rpcs[rpc_method].request_type.new(request) if request.is_a?(Hash)

          outer_request_params = {
            :service_name => subject_service.to_s,
            :method_name => rpc_method.to_s,
            :request_proto => request.serialize_to_string
          }

          outer_request = ::Protobuf::Socketrpc::Request.new(outer_request_params)
          dispatcher = ::Protobuf::Rpc::ServiceDispatcher.new(outer_request)

          dispatcher.invoke!
        end

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
        #       mock_rpc(Proto::UserService, :client, response: mock('response_mock', status: 'success'))
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
        #       mock_rpc(Proto::UserService, :client, error: mock('error_mock', message: 'this is an error message'))
        #       ErrorReporter.should_receive(:report).with('this is an error message')
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
        #       mock_rpc(Proto::UserService, :client, request: expected_request)
        #       create_user(request)
        #     end
        #
        # @example Testing the given client request object (explicit assert)
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
        # @param [Block] assert_block when given, will be invoked with the request message sent to the client method
        # @return [Mock] the stubbed out client mock
        def mock_rpc(klass, method, callbacks={}, &assert_block)
          client = double('Client', :on_success => true, :on_failure => true)
          client.stub(method).and_yield(client)

          klass.stub(:client).and_return(client)

          if callbacks[:request]
            client.should_receive(method).with(callbacks[:request])
          elsif block_given?
            client.should_receive(method) do |given_req|
              assert_block.call(given_req)
            end
          else
            client.should_receive(method)
          end

          client.stub(:on_success).and_yield(callbacks[:response]) if callbacks[:response]
          client.stub(:on_failure).and_yield(callbacks[:error]) if callbacks[:error]

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
      end
    end
  end
end
