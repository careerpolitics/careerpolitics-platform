# Renders Mermaid diagrams to inline SVG at save-time using mermaid-cli (mmdc).
#
# Usage in articles:
#   {% mermaid %}
#   graph TD
#     A[Start] --> B[End]
#   {% endmermaid %}
#
# Requires: @mermaid-js/mermaid-cli installed globally or via npx.
#   npm install -g @mermaid-js/mermaid-cli
#
class MermaidTag < Liquid::Block
  include ActionView::Helpers::SanitizeHelper

  PARTIAL = "liquids/mermaid".freeze

  def render(_context)
    raw_definition = Nokogiri::HTML.parse(super).at("body").text.strip

    svg_output = render_mermaid_svg(raw_definition)

    html = ApplicationController.render(
      partial: PARTIAL,
      locals: {
        svg_content: svg_output,
        raw_definition: raw_definition,
      },
      )
    # Collapse whitespace between HTML tags so the second Redcarpet pass in
    # MarkdownProcessor::Parser#finalize treats the output as one HTML block
    # instead of interpreting indented SVG paths as code blocks and blank
    # lines as block breaks.
    html.gsub(/>\s*\n\s*</, "> <").gsub(/\A\s+/, "").gsub(/\s+\z/, "")
  end

  private

  def render_mermaid_svg(definition)
    require "open3"
    require "tempfile"

    input_file = Tempfile.new(["mermaid", ".mmd"])
    output_file = Tempfile.new(["mermaid", ".svg"])

    begin
      input_file.write(definition)
      input_file.close

      mmdc_path = find_mmdc
      raise StandardError, "mermaid-cli (mmdc) not found. Install with: npm install -g @mermaid-js/mermaid-cli" unless mmdc_path

      config_path = mermaid_config_path

      cmd = [
        mmdc_path,
        "-i", input_file.path,
        "-o", output_file.path,
        "-e", "svg",
        "--quiet",
      ]
      cmd += ["-c", config_path] if config_path && File.exist?(config_path)

      _stdout, stderr, status = Open3.capture3(*cmd)

      unless status.success?
        Rails.logger.error("MermaidTag render failed: #{stderr}")
        return fallback_html(definition, stderr)
      end

      svg = File.read(output_file.path)
      sanitize_svg(svg)
    rescue StandardError => e
      Rails.logger.error("MermaidTag error: #{e.message}")
      fallback_html(definition, e.message)
    ensure
      input_file.close unless input_file.closed?
      output_file.close unless output_file.closed?
      input_file.unlink rescue nil
      output_file.unlink rescue nil
    end
  end

  def find_mmdc
    require "open3"

    candidates = if Gem.win_platform?
                   %w[mmdc.cmd mmdc]
                 else
                   %w[mmdc]
                 end

    candidates.each do |candidate|
      _output, status = Open3.capture2e("#{candidate} --version")
      return candidate if status.success?
    rescue Errno::ENOENT
      next
    end

    nil
  end

  def mermaid_config_path
    config = Rails.root.join("config", "mermaid.json")
    config.exist? ? config.to_s : nil
  end

  def sanitize_svg(svg)
    # Extract just the <svg>...</svg> content, strip any XML declarations
    svg_match = svg.match(%r{<svg[\s\S]*</svg>}m)
    return svg unless svg_match

    svg_content = svg_match[0]
    # Add responsive class
    svg_content.sub("<svg", '<svg class="mermaid-diagram" style="max-width: 100%; height: auto;"')
  end

  def fallback_html(definition, error_message = nil)
    escaped = ERB::Util.html_escape(definition)
    error_note = error_message ? "<p class=\"mermaid-error\">Render error: #{ERB::Util.html_escape(error_message)}</p>" : ""
    <<~HTML
      <div class="mermaid-fallback">
        #{error_note}
        <pre><code>#{escaped}</code></pre>
      </div>
    HTML
  end
end

Liquid::Template.register_tag("mermaid", MermaidTag)
