class TestJob
  include Sidekiq::Job
  def perform(name, count)
    pp "this job is running #{name}, #{count}"
    sleep 3
    pp "this job is ending"
  end
end
