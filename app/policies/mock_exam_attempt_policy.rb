class MockExamAttemptPolicy < ApplicationPolicy
  def create?
    require_user_in_good_standing!
    user.cached_base_subscriber?
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

    0
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
end
