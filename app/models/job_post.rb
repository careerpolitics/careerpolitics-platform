class JobPost < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :post_type, inclusion: { in: %w[new_update admit_card online_form] }, allow_nil: true
  validates :employment_type, inclusion: { in: %w[full_time part_time contract internship temporary] }, allow_nil: true
  validates :vacancies, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :link, presence: true, if: :published?
  validates :color, format: { with: /\A#[0-9a-fA-F]{3,8}\z/, message: "must be a valid hex color (e.g. #ff5733)" }, allow_blank: true
  validate :link_format, if: :published?

  def link_format
    return if link.blank?
    # Allow relative URLs (starting with /) or absolute URLs (http/https)
    return if link.start_with?('/') || link.match?(/\Ahttps?:\/\//)
    errors.add(:link, 'must be a valid URL (starting with http://, https://, or /)')
  end

  before_validation :generate_slug, on: :create
  before_validation :assign_auto_color, on: :create
  before_save :set_published_at, if: :published_changed?

  scope :published, -> { where(published: true) }
  scope :approved, -> { where(approved: true) }
  scope :available, -> { published.approved }
  scope :by_post_type, ->(type) { where(post_type: type) }
  scope :by_category, ->(category) { where(category: category) }
  scope :recent, -> { order(position: :asc, published_at: :desc, created_at: :desc) }
  scope :featured, -> { available.where(featured: true).recent.limit(8) }
  scope :pending_approval, -> { where(approved: false) }

  POST_TYPES = {
    new_update: 'new_update',
    admit_card: 'admit_card',
    online_form: 'online_form'
  }.freeze

  FEATURED_COLORS = %w[
    #0056b3 #e63946 #2a9d8f #e76f51 #6a4c93
    #1d3557 #457b9d #f4a261 #264653 #d62828
  ].freeze

  def to_param
    slug
  end

  def path
    "/jobs/#{slug}"
  end

  def badge_type
    return nil unless published_at
    return 'last_day' if deadline_at.present? && deadline_at > Time.current && deadline_at <= 24.hours.from_now
    return 'new' if published_at > 3.days.ago
    nil
  end


  def employment_type_schema_value
    return nil if employment_type.blank?

    {
      "full_time" => "FULL_TIME",
      "part_time" => "PART_TIME",
      "contract" => "CONTRACTOR",
      "internship" => "INTERN",
      "temporary" => "TEMPORARY"
    }[employment_type]
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
    while JobPost.exists?(slug: self.slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  def set_published_at
    self.published_at = Time.current if published? && published_at.nil?
  end

  def assign_auto_color
    return if color.present?

    self.color = FEATURED_COLORS[JobPost.count % FEATURED_COLORS.size]
  end
end
