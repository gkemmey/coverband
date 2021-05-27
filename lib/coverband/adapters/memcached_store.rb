# frozen_string_literal: true

module Coverband
  module Adapters
    class MemcachedStore < Base
      MEMCACHED_STORAGE_FORMAT_VERSION = "memcached_1_0"
      MAX_RETRIES = 10

      def initialize(memcached)
        super()
        @memcached = memcached

        # TODO: take from @redis_ttl default. make configurable?
        @ttl = 2_592_000 # in seconds. Default is 30 days.
        @format_version = MEMCACHED_STORAGE_FORMAT_VERSION

        @keys = {}
        Coverband::TYPES.each do |type|
          @keys[type] = [@format_version, type].compact.join(".")
        end
      end

      def clear!
        Coverband::TYPES.each do |type|
          @memcached.delete(type_base_key(type))
        end
      end

      def clear_file!(filename)
        Coverband::TYPES.each do |type|
          @memcached.add(type_base_key(type), {}, @ttl)
          MAX_RETRIES.times do
            break if @memcached.cas(type_base_key(type), @ttl) do |data|
              data = parsed(data)
              data.delete(filename)
              data
            end
          end
        end
      end

      def size
        # TODO: what if your memcached client is using a different serializer? wher if you're not
        #       using dalli?
        @memcached.get(base_key) ? Marshal.dump(@memcached.get(base_key)).bytesize : "N/A"
      end

      def migrate!
        raise NotImplementedError, "MemcachedStore doesn't support migrations"
      end

      def type=(type)
        super
        reset_base_key
      end

      def coverage(local_type = nil, opts = {})
        local_type ||= opts.key?(:override_type) ? opts[:override_type] : type
        data = @memcached.get type_base_key(local_type)
        parsed(data, opts)
      end

      def save_report(report, local_type = nil)
        local_type ||= type

        @memcached.add(type_base_key(local_type), {}, @ttl)
        MAX_RETRIES.times do
          break if @memcached.cas(type_base_key(local_type), @ttl) do |data|
            merge_reports(report.dup, parsed(data, skip_hash_check: true))
          end
        end
      end

      def raw_store
        @memcached
      end

      private

      def parsed(cache_hit, opts = {})
        data = cache_hit || {}
        data.delete_if { |file_path, file_data| file_hash(file_path) != file_data["file_hash"] } unless opts[:skip_hash_check]
        data
      end

      def reset_base_key
        @base_key = nil
      end

      def base_key
        @base_key ||= [@format_version, type].compact.join(".")
      end

      def type_base_key(local_type)
        @keys[local_type]
      end
    end
  end
end
