class JobPost < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :post_type,
            format: { with: /\A[a-z0-9_\-]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" },
            allow_blank: true
  validates :link, presence: true, if: :published?
  validate :link_format, if: :published?

  before_validation :generate_slug, on: :create
  before_save :set_published_at, if: :published_changed?

  scope :published, -> { where(published: true) }
  scope :approved, -> { where(approved: true) }
  scope :available, -> { published.approved }
  scope :by_post_type, ->(type) { where(post_type: type) }
  scope :recent, -> { order(position: :asc, published_at: :desc, created_at: :desc) }
  scope :featured, -> { available.where(featured: true).recent.limit(8) }
  scope :pending_approval, -> { where(approved: false) }
  scope :with_post_type, -> { where.not(post_type: [nil, ""]) }

  def self.available_post_types
    available.with_post_type.distinct.order(:post_type).pluck(:post_type)
  end

  def self.all_post_types
    with_post_type.distinct.order(:post_type).pluck(:post_type)
  end

  def self.post_type_label(post_type)
    post_type.to_s.tr("_", " ").titleize
  end

  def self.index_sections(limit: 10)
    available_post_types.map do |post_type|
      posts = available.by_post_type(post_type).includes(:user).recent.page(1).per(limit)
      {
        post_type: post_type,
        title: post_type_label(post_type),
        icon: post_type_icon(post_type),
        posts: posts,
        pagination_param: "#{post_type}_page"
      }
    end
  end

  def self.post_type_icon(post_type)
    {
      "new_update" => "fas fa-bell",
      "admit_card" => "fas fa-ticket-alt",
      "online_form" => "fas fa-file-alt"
    }.fetch(post_type, "fas fa-briefcase")
  end

  def link_format
    return if link.blank?
    return if link.start_with?("/") || link.match?(/\Ahttps?:\/\//)

    errors.add(:link, "must be a valid URL (starting with http://, https://, or /)")
  end

  def to_param
    slug
  end

  def path
    "/jobs/#{slug}"
  end

  def badge_type
    return nil unless published_at
    return "new" if published_at > 3.days.ago

    nil
  end

  def related_jobs(limit: 4)
    JobPost.available
      .where.not(id: id)
      .where(post_type: post_type)
      .recent
      .limit(limit)
  end

  def available?
    published? && approved?
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = title.parameterize
    self.slug = base_slug
    counter = 1
    while JobPost.exists?(slug: slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def set_published_at
    self.published_at = Time.current if published? && published_at.nil?
  end
end
