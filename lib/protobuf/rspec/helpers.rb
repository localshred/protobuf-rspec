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
        # @param [String] a string message indicating an rpc_failed expectation.
        # @param [block] optionally provide a block which will be yielded the service instance just prior to invoking the rpc method.
        # @return [Protobuf::Service] the service instance post-calling the rpc method.
        def local_rpc(rpc_method, request, expected_error = nil)
          request = subject_service.rpcs[rpc_method].request_type.new(request) if request.is_a?(Hash)
          service = subject_service.new(rpc_method, request.serialize_to_string)

          if block_given?
            $stderr.puts '[Warning] Ignoring error expectation %s due to given block' % expected_error unless expected_error.blank?
            yield(service)
          else
            if expected_error.blank?
              service.should_not_receive(:rpc_failed)
            else
              service.should_receive(:rpc_failed).with(expected_error)
            end
          end

          service.__send__(rpc_method)
          service
        end

        # Provides backwards compatability to bridge to the new local_rpc usage.
        #
        def call_local_service(klass, rpc_method, request, &block)
          $stderr.puts '[Deprecated] call_local_service is deprecated. Please use local_rpc in conjunction with subject_service.'
          self.class.service { klass }
          local_rpc(rpc_method, request, nil &block)
        end
        alias_method :call_service, :call_local_service

        # Create a mock service that responds in the way you are expecting to aid in testing client -> service calls.
        # In order to test your success callback you should provide a :response object. Similarly, to test your failure
        # callback you should provide an :error object.
        #
        # Asserting the request object can be done one of two ways: direct or explicit. If you would like to directly test
        # the object that is given as a request you should provide a :request object as part of the cb_mocks third parameter hash.
        # Alternatively you can do an explicit assertion by providing a block to mock_remote_service. The block will be yielded with
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
        #       mock_remote_service(Proto::UserService, :client, response: mock('response_mock', status: 'success'))
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
        #       mock_remote_service(Proto::UserService, :client, error: mock('error_mock', message: 'this is an error message'))
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
        #       mock_remote_service(Proto::UserService, :client, request: expected_request)
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
        #       mock_remote_service(Proto::UserService, :client) do |given_request|
        #         given_request.field1.should eq 'rainbows'
        #         given_request.field2.should eq 'ponies'
        #       end
        #       create_user(request)
        #     end
        #
        # @param [Class] klass the service class constant
        # @param [Symbol, String] method a symbol or string denoting the method to call
        # @param [Hash] cb_mocks provides expectation objects to invoke on_success (with :response), on_failure (with :error), and the request object (:request)
        # @param [Block] assert_block when given, will be invoked with the request message sent to the client method
        # @return [Mock] the stubbed out client mock
        def mock_remote_service(klass, method, cb_mocks={}, &assert_block)
          self.class.subject_service { klass }
          mock_rpc(method, callbacks, &assert_block)
        end
        alias_method :mock_service, :mock_remote_service

        def mock_rpc(method, callbacks = {}, &assert_block)
          client = double('Client', :on_success => true, :on_failure => true)
          client.stub(method).and_yield(client)

          subject_service.stub(:client).and_return(client)

          if cb_mocks[:request]
            client.should_receive(method).with(cb_mocks[:request])
          elsif block_given?
            client.should_receive(method) do |given_req|
              assert_block.call(given_req)
            end
          else
            client.should_receive(method)
          end

          client.stub(:on_success).and_yield(cb_mocks[:response]) if cb_mocks[:response]
          client.stub(:on_failure).and_yield(cb_mocks[:error]) if cb_mocks[:error]

          client
        end

      end

    end
  end
end
