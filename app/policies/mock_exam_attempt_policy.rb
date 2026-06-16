class MockExamAttemptPolicy < ApplicationPolicy
  DAILY_FREE_LIMIT = 1

  def create?
    require_user_in_good_standing!
    return true if user.cached_base_subscriber?

    daily_attempts_used < DAILY_FREE_LIMIT
  end

  def show?
    record.user_id == user.id || user_any_admin?
  end

  def submit?
    record.user_id == user.id
  end

  def results?
    show?
  end

  def daily_attempts_remaining
    return nil if user.cached_base_subscriber?

    [DAILY_FREE_LIMIT - daily_attempts_used, 0].max
  end

  class Scope < Scope
    def resolve
      if user.any_admin?
        scope.all
      else
        scope.where(user: user)
      end
    end
  end

  private

  def daily_attempts_used
    user.mock_exam_attempts.where("created_at >= ?", Time.current.beginning_of_day).count
  end
end
