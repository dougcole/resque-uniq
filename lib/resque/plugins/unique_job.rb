module Resque
  module Plugins
    module UniqueJob
      LOCK_AUTOEXPIRE_PERIOD = 21600 # 6 hours
      LOCK_NAME_PREFIX = 'lock'
      RUN_LOCK_NAME_PREFIX = 'running_'

      def lock(*args)
        "#{LOCK_NAME_PREFIX}:#{name}-#{obj_to_string(args)}"
      end

      def run_lock(*args)
        run_lock_from_lock(lock(*args))
      end

      def run_lock_from_lock(lock)
        "#{RUN_LOCK_NAME_PREFIX}#{lock}"
      end

      def lock_from_run_lock(rlock)
        rlock.sub(/^#{RUN_LOCK_NAME_PREFIX}/, '')
      end

      def stale_lock?(lock)
        return false unless Resque.redis.get(lock)

        rlock = run_lock_from_lock(lock)
        return false unless Resque.redis.get(rlock)

        Resque.working.map {|w| w.job }.map do |item|
          payload = item['payload']
          klass = Resque::Job.constantize(payload['class'])
          args = payload['args']
          return false if rlock == klass.run_lock(*args)
        end
        true
      end

      def before_enqueue_lock(*args)
        lock_name = lock(*args)
        if stale_lock? lock_name
          Resque.redis.del lock_name
          Resque.redis.del "#{RUN_LOCK_NAME_PREFIX}#{lock_name}"
        end
        nx = Resque.redis.setnx(lock_name, Time.now.to_i)
        ttl = defined?(@lock_autoexpire_period) ? @lock_autoexpire_period : LOCK_AUTOEXPIRE_PERIOD
        Resque.redis.expire(lock_name, ttl) if ttl > 0
        nx
      end

      def around_perform_lock(*args)
        rlock = run_lock(*args)
        Resque.redis.set(rlock, Time.now.to_i)

        begin
          yield
        ensure
          Resque.redis.del(rlock)
          Resque.redis.del(lock(*args))
        end
      end


      private

      def obj_to_string(obj)
        case obj
        when Hash
          s = []
          obj.keys.sort.each do |k|
            s << obj_to_string(k)
            s << obj_to_string(obj[k])
          end
          s.to_s
        when Array
          s = []
          obj.each { |a| s << obj_to_string(a) }
          s.to_s
        else
          obj.to_s
        end
      end
    end
  end
end