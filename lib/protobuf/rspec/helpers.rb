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
      # @param [Class] klass the service class constant.
      # @param [Symbol, String] method a symbol or string denoting the method to call.
      # @param [Protobuf::Message or Hash] request the request message of the expected type for the given method.
      # @param [block] optionally provide a block which will be yielded the service instance just prior to invoking the rpc method.
      # @return [Protobuf::Service] the service instance post-calling the rpc method.
      def call_local_service(klass, method_name, request)
        request = service.rpcs[method_name].request_type.new(request) if request.is_a?(Hash)
        service = klass.new(method_name, request.serialize_to_string)
        yield(service) if block_given?
        service.method(method_name).call
        service
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
        klass.stub(:client).and_return(client = mock('Client'))
        client.stub(method).and_yield(client)
        if cb_mocks[:request]
          client.should_receive(method).with(cb_mocks[:request])
        elsif block_given?
          client.should_receive(method) do |given_req|
            assert_block.call(given_req)
          end
        else
          client.should_receive(method)
        end

        if cb_mocks[:response]
          client.stub(:on_success).and_yield(cb_mocks[:response])
        else
          client.stub(:on_success)
        end

        if cb_mocks[:error]
          client.stub(:on_failure).and_yield(cb_mocks[:error])
        else
          client.stub(:on_failure)
        end

        client
      end
      alias_method :mock_service, :mock_remote_service

    end
  end
end
