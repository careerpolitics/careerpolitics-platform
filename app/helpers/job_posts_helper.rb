module JobPostsHelper
  REMOTE_LOCATION_REGEX = /(remote|work\s*from\s*home|wfh|telecommute)/i

  def job_post_internal_link(job_post)
    raw_link = job_post.link.to_s.strip
    return job_posts_path if raw_link.blank?
    return raw_link if raw_link.start_with?("/")

    uri = URI.parse(raw_link)
    return uri.request_uri if uri.host == request&.host

    job_posts_path
  rescue URI::InvalidURIError
    job_posts_path
  end

  def remote_job?(job_post)
    job_post.location.to_s.match?(REMOTE_LOCATION_REGEX)
  end

  def job_post_schema_description(job_post)
    article_description = article_description_from_link(job_post.link)
    return article_description if article_description.present?

    job_post.description.presence || job_post.title
  end

  def article_description_from_link(link)
    path = normalized_internal_path(link)
    return if path.blank? || path.start_with?("/jobs")

    Article.published.from_subforem.find_by(path: path)&.description
  end

  def normalized_internal_path(link)
    raw_link = link.to_s.strip
    return if raw_link.blank?
    return raw_link if raw_link.start_with?("/")

    uri = URI.parse(raw_link)
    return uri.request_uri if uri.host == request&.host
  rescue URI::InvalidURIError
    nil
  end

  def job_posting_schema(job_post)
    schema = {
      "@type" => "JobPosting",
      "title" => job_post.title,
      "description" => job_post_schema_description(job_post),
      "url" => "#{request.base_url}#{job_post_internal_link(job_post)}",
      "datePosted" => job_post.created_at.iso8601,
      "hiringOrganization" => {
        "@type" => "Organization",
        "name" => job_post.organization_name.presence || Settings::Community.community_name
      },
      "employmentType" => job_post.employment_type_schema_value,
      "validThrough" => job_post.deadline_at&.iso8601,
      "baseSalary" => (job_post.salary_range.present? ? {
        "@type" => "MonetaryAmount",
        "value" => {
          "@type" => "QuantitativeValue",
          "value" => job_post.salary_range,
          "unitText" => "MONTH"
        }
      } : nil)
    }

    if remote_job?(job_post)
      schema["jobLocationType"] = "TELECOMMUTE"
      schema["applicantLocationRequirements"] = {
        "@type" => "Country",
        "name" => "India"
      }
    else
      schema["jobLocation"] = {
        "@type" => "Place",
        "address" => {
          "@type" => "PostalAddress",
          "addressLocality" => job_post.location.presence || "India",
          "addressCountry" => "IN"
        }
      }
    end

    schema.compact
  end
end
