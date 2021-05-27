# frozen_string_literal: true

require File.expand_path("../../test_helper", File.dirname(__FILE__))

class MemcachedStoreTest < Minitest::Test
  def setup
    super
    @store = Coverband::Adapters::MemcachedStore.new(Dalli::Client.new("localhost:11211"))
    @memcached = @store.raw_store

    @global_store, Coverband.configuration.store = Coverband.configuration.store, @store
  end

  def teardown
    @store.clear!
    Coverband.configuration.store = @global_store
  end

  def test_coverage
    mock_file_hash
    expected = basic_coverage
    @store.save_report(expected)
    assert_equal expected.keys, @store.coverage.keys
    @store.coverage.each_pair do |key, data|
      assert_equal expected[key], data["data"]
    end
  end

  def test_coverage_increments
    mock_file_hash
    expected = basic_coverage.dup
    @store.save_report(basic_coverage.dup)
    assert_equal expected.keys, @store.coverage.keys
    @store.coverage.each_pair do |key, data|
      assert_equal expected[key], data["data"]
    end
    current_time = Time.now.to_i
    @store.save_report(basic_coverage.dup)
    assert_equal [0, 2, 4], @store.coverage["app_path/dog.rb"]["data"]
    assert current_time <= @store.coverage["app_path/dog.rb"]["last_updated_at"]
  end

  def test_file_hash_change
    mock_file_hash(hash: "abc")
    @store.save_report("app_path/dog.rb" => [0, nil, 1, 2])
    assert_equal [0, nil, 1, 2], @store.coverage["app_path/dog.rb"]["data"]
    mock_file_hash(hash: "123")
    assert_nil @store.coverage["app_path/dog.rb"]
  end

  def test_store_coverage_by_type
    mock_file_hash
    expected = basic_coverage
    @store.type = :eager_loading
    @store.save_report(expected)
    assert_equal expected.keys, @store.coverage.keys
    @store.coverage.each_pair do |key, data|
      assert_equal expected[key], data["data"]
    end
    @store.type = Coverband::RUNTIME_TYPE
    assert_equal [], @store.coverage.keys
  end

  def test_merged_coverage_with_types
    mock_file_hash
    assert_equal Coverband::RUNTIME_TYPE, @store.type
    @store.type = :eager_loading
    @store.save_report("app_path/dog.rb" => [0, 1, 1])
    # eager_loading doesn't set last_updated_at
    assert_nil @store.coverage["app_path/dog.rb"]["last_updated_at"]
    @store.type = Coverband::RUNTIME_TYPE
    current_time = Time.now.to_i
    @store.save_report("app_path/dog.rb" => [1, 0, 1])
    assert_equal [1, 1, 2], @store.get_coverage_report[:merged]["app_path/dog.rb"]["data"]
    assert current_time <= @store.coverage["app_path/dog.rb"]["last_updated_at"]
    assert_equal Coverband::RUNTIME_TYPE, @store.type
  end

  def test_coverage_for_file
    mock_file_hash
    expected = basic_coverage
    @store.save_report(expected)
    assert_equal example_line, @store.coverage["app_path/dog.rb"]["data"]
  end

  def test_coverage_with_simulate_oneshot_lines_coverage
    Coverband.configuration.stubs(:simulate_oneshot_lines_coverage).returns(true)
    mock_file_hash
    expected = basic_coverage
    @store.save_report(expected)
    assert_equal example_line, @store.get_coverage_report[:runtime]["app_path/dog.rb"]["data"]
  end

  def test_coverage_when_null
    assert_nil @store.coverage["app_path/dog.rb"]
  end

  def test_clear
    call_count = 0
    @memcached.stub(:delete, ->(*args) { call_count += 1 }) do
      @store.clear!
      assert_equal 2, call_count
    end
  end

  def test_clear_file
    mock_file_hash
    @store.type = :eager_loading
    @store.save_report("app_path/dog.rb" => [0, 1, 1])
    @store.type = Coverband::RUNTIME_TYPE
    @store.save_report("app_path/dog.rb" => [1, 0, 1])
    assert_equal [1, 1, 2], @store.get_coverage_report[:merged]["app_path/dog.rb"]["data"]
    @store.clear_file!("app_path/dog.rb")
    assert_nil @store.get_coverage_report[:merged]["app_path/dog.rb"]
  end

  def test_size
    mock_file_hash
    @store.type = :eager_loading
    @store.save_report("app_path/dog.rb" => [0, 1, 1])
    assert @store.size > 1
  end

  def test_base_key
    assert @store.send(:base_key).end_with?(Coverband::RUNTIME_TYPE.to_s)
  end
end
