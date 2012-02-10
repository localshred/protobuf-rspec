protobuf-rspec gem
==================

RSpec Helpers designed to give you mock abstraction of client or service layer. Require as protobuf/rspec/helpers and include into your running RSpec configuration.

**Note:** Tested to work with the [protobuf gem](https://rubygems.org/gems/protobuf) (>= 1.0).

Mocking Client Requests (Outside-In test of the service methods)
----------------------------------------------------------------

Use this method to call a local service in your application to test responses and behavior based on the given request. This should be used to outside-in test a local RPC Service without testing the underlying socket implementation or needing actual client code to invoke the method(s) under test.

Given the service implementation below:

```ruby
module Proto
  class UserService < Protobuf::Rpc::Service
    def create
      user = User.create_from_proto(request)
      self.response = ProtoRepresenter.new(user).to_proto
    end
  end
end
```

This could be one way to test the implementation while ignoring the RPC backend:


```ruby
describe Proto::UserService do
  describe '#create' do
    it 'creates a new user' do
      create_request = Proto::UserCreate.new(...)
      client = call_local_service(Proto::UserService, :create, create_request)
      client.response.should eq(some_response_object)
    end
  end
end
```

Mocking Service Responses
-------------------------

Create a mock service that responds in the way you are expecting to aid in testing client -> service calls. In order to test your success callback you should provide a `:response` object. Similarly, to test your failure callback you should provide an `:error` object. 

Asserting the request object can be done one of two ways: direct or explicit. If you would like to directly test the object that is given as a request you should provide a `:request` object as part of the `cb_mocks` hash (third parameter). Alternatively you can do an explicit assertion by providing a block to `mock_remote_service`. The block will be yielded with the request object as its only parameter. This allows you to perform your own assertions on the request object (e.g. only check a few of the fields in the request). Also note that if a `:request` param is given in the third param, the block will be ignored.

### Testing the client on_success callback
```ruby
  # Method under test
  def create_user(request)
    status = 'unknown'
    Proto::UserService.client.create(request) do |c|
      c.on_success do |response|
        status = response.status
      end
    end
    status
  end
  ...
  
  # spec
  it 'verifies the on_success method behaves correctly' do
    mock_remote_service(Proto::UserService, :client, response: mock('response_mock', status: 'success'))
    create_user(request).should eq('success')
  end
```

### Testing the client on_failure callback
```ruby
# Method under test
def create_user(request)
  status = nil
  Proto::UserService.client.create(request) do |c|
    c.on_failure do |error|
      status = 'error'
      ErrorReporter.report(error.message)
    end
  end
  status
end
...

# spec
it 'verifies the on_success method behaves correctly' do
  mock_remote_service(Proto::UserService, :client, error: mock('error_mock', message: 'this is an error message'))
  ErrorReporter.should_receive(:report).with('this is an error message')
  create_user(request).should eq('error')
end
```

### Testing the given client request object (direct assert)
```ruby
# Method under test
def create_user
  request = ... # some operation to build a request on state
  Proto::UserService.client.create(request) do |c|
    ...
  end
end
...

# spec
it 'verifies the request is built correctly' do
  expected_request = ... # some expectation
  mock_remote_service(Proto::UserService, :client, request: expected_request)
  create_user(request)
end
```

### Testing the given client request object (explicit assert)
```ruby
# Method under test
def create_user
  request = ... # some operation to build a request on state
  Proto::UserService.client.create(request) do |c|
    ...
  end
end
...

# spec
it 'verifies the request is built correctly' do
  mock_remote_service(Proto::UserService, :client) do |given_request|
    given_request.field1.should eq 'rainbows'
    given_request.field2.should eq 'ponies'
  end
  create_user(request)
end
````

Feedback
--------

Feedback and comments are welcome:

Web: [rand9.com](http://rand9.com)
Twitter: [@localshred](https://twitter.com/localshred)
Github: [github](https://github.com/localshred)
