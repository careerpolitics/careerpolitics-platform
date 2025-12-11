class JobPostPolicy < ApplicationPolicy
  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    true
  end

  def show?
    true
  end

  def create?
    require_user!
    require_user_in_good_standing!
    true
  end

  def new?
    create?
  end

  def update?
    require_user!
    require_user_in_good_standing!
    user_author? || user_super_admin? || user_any_admin?
  end

  def edit?
    update?
  end

  private

  def user_author?
    record.user_id == user.id
  end
end

