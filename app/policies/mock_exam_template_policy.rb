class MockExamTemplatePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    record.active? && record.published?
  end

  def create?
    user_any_admin?
  end

  def update?
    user_any_admin?
  end

  def destroy?
    user_super_admin?
  end

  class Scope < Scope
    def resolve
      if user&.any_admin?
        scope.all
      else
        scope.active_published
      end
    end
  end
end
