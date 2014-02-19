protobuf-rspec gem
==================

Provides spec helpers for testing client and server [protobuf](https://github.com/localshred/protobuf) code.

RSpec Helpers are designed to give you mock abstraction of client or service layer. Require as `protobuf/rspec` and include into your running RSpec configuration.

```ruby
# spec_helper.rb
# ...

require 'protobuf/rspec'
RSpec.configure do |config|
  config.include Protobuf::RSpec::Helpers
end
```

Unit-Testing Service Behavior
-----------------------------

### `local_rpc`

To unit test your service you should use the `local_rpc` helper method. `local_rpc` helps you call the service instance method of your choosing to ensure that the correct responses are generated with the given requests. This should be used to outside-in test a local RPC Service without testing the underlying socket implementation or needing actual client code to invoke the endpoint method under test. Any filters added to the service **will** be invoked.

Given the service implementation below:

```ruby
module Services
  class UserService < Protobuf::Rpc::Service
    def create
      if request.name
        user = User.create_from_proto(request)
        respond_with(user)
      else
        rpc_failed 'Error: name required'
      end
    end

    def notify
      user = User.find_by_guid(request.guid)
      if user
        Resque.enqueue(EmailUserJob, user.id)
        respond_with(:queued => true)
      else
        rpc_failed 'Error: user not found'
      end
    end
  end
end
```

Specs that test these two methods and their various cases could look something like this:

```ruby
describe Services::UserService do
  describe '#create' do
    subject { local_rpc(:create, request) }

    context 'when request is valid' do
      let(:request) { { :name => 'Jack' } }
      let(:user_mock) { FactoryGirl.build(:user) }
      before { User.should_receive(:create_from_proto).and_return(user_mock) }
      it { should eq(user_mock) }
    end

    context 'when name is not given' do
      let(:request) { :name => '' }
      it { should =~ /Error/ }
    end
  end

  describe '#notify' do
    let(:request) { { :guid => 'USR-123' } }
    let(:user_mock) { FactoryGirl.build(:user) }
    subject { local_rpc(:notify, request) }

    context 'when user is found' do
      before { User.should_receive(:find_by_guid).with(request.guid).and_return(user_mock) }
      before { Resqueue.should_receive(:enqueue).with(EmailUserJob, request.guid)
      its(:queued) { should be_true }
    end

    context 'when user is not found' do
      before { Resque.should_not_receive(:enqueue) }
      it { should =~ /Error/ }
    end
  end
end
```

### `rpc`

Make an RPC call (without testing the underlying socket implementation). Works the same as `local_rpc`, but invokes the entire RPC middleware stack (service filters are also run):

```Ruby
rpc(:create, user_request) # => UserService#create
```

### `rpc_env`

Initialize a new RPC env object simulating what happens in the middleware stack.
Useful for testing a service class directly without using `rpc` or `local_rpc`.

```Ruby
describe "#create" do
  # Initialize request and response
  # ...
  let(:env) { rpc_env(:create, request) }

  subject { described_class.new(env) }

  it "creates a user" do
    subject.create
    subject.response.should eq response
  end
end
```

### `subject_service`

One thing to note is that `local_rpc` uses `described_class` as the class to invoke for the given method. If you need to instead test a different class than your `described_class`, simply pass a block to `subject_service` which returns the class you would like to use instead.

```ruby
describe 'The User Service' do
  subject_service { Services::UserService }

  describe '#create' do
    subject { local_rpc(:create, request) }
    # ...
  end

  #...
end
```

### `request_class` and `response_class`

Both the `request_class` and `response_class` helper methods will return the class type for, you guessed it, the request and response type defined by the service method. This can aid in setting up the correct objects for expectations. Simply pass in the name of the endpoint you are testing to get the appropriate message class.

```ruby
request_class(:create) # => UserCreateRequest
response_class(:create) # => User
```
Mocking Service Responses
-------------------------

Create a mock service that responds in the way you are expecting to aid in testing client -> service calls. In order to test your success callback you should provide a `:success` option. To test your failure callback you should provide a `:failure` option.


### Testing the client `on_success` callback

Passing a `:success` key as an option to `mock_rpc` will cause the `on_success` callback to be invoked with the given object. In this way you can simulate a successful service response to verify that you are handling the response appropriately. You can alternatively use the `:response` key to invoke the `on_success` block.

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
    response_mock = mock('response_mock', :status => 'success')
    mock_rpc(Proto::UserService, :client, :success => response_mock) # alternatively can use :response key here
    create_user(request).should eq('success')
  end
```

### Testing the client `on_failure` callback

Passing a `:failure` key as an option to `mock_rpc` will cause the `on_failure` callback to be invoked with the given object. In this way you can simulate a service failure and verify you are handling that failure appropriately. You can alternatively use the `:error` key to invoke the `on_failure` block.

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
  error_mock = mock('error_mock', :message => 'this is an error message')
  mock_rpc(Proto::UserService, :client, :failure => error_mock) # alternatively can use :error key here
  ErrorReporter.should_receive(:report).with(error_mock.message)
  create_user(request).should eq('error')
end
```

### Testing the given client request object (direct assert)

In order to test the request object sent to the service you can pass a `:request` key whose value will be asserted with RSpec's `with` constraint paired with the `should_receive` assertion. Also note that if a `:request` option is given, the assert block will be ignored (see below).

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
  mock_rpc(Proto::UserService, :client, :request => expected_request)
  create_user(request)
end
```

### Testing the given client request object (block assert)

You can also pass a block to `mock_rpc` which will be yielded the request object. This allows more fine-grained assertions on the request object. Also note that if a `:request` option is given (see above), the assert block will be ignored.

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
  mock_rpc(Proto::UserService, :client) do |given_request|
    given_request.field1.should eq 'rainbows'
    given_request.field2.should eq 'ponies'
  end
  create_user(request)
end
````

Feedback
--------

Feedback and comments are welcome:

Twitter: [@localshred](https://twitter.com/localshred)
Github: [github](https://github.com/localshred)
