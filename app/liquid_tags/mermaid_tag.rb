# Renders Mermaid diagrams client-side via the mermaid.js library.
#
# Usage in articles:
#   {% mermaid %}
#   graph TD
#     A[Start] --> B[End]
#   {% endmermaid %}
#
# No server-side dependencies required. The mermaid JS library renders
# diagrams in the browser when the page loads.
#
class MermaidTag < Liquid::Block
  PARTIAL = "liquids/mermaid".freeze
  MERMAID_CDN_VERSION = "11".freeze

  SCRIPT = <<~JAVASCRIPT.freeze
    <script type="module">
      if (!window.__mermaidLoaded) {
        window.__mermaidLoaded = true;
        import('https://cdn.jsdelivr.net/npm/mermaid@#{MERMAID_CDN_VERSION}/dist/mermaid.esm.min.mjs')
          .then(function(mod) {
            mod.default.initialize({ startOnLoad: false, theme: 'default' });
            mod.default.run({ querySelector: '.mermaid' });
          });
      }
    </script>
  JAVASCRIPT

  def self.script
    SCRIPT
  end

  def render(_context)
    raw_definition = Nokogiri::HTML.parse(super).at("body").text.strip

    html = ApplicationController.render(
      partial: PARTIAL,
      locals: {
        raw_definition: raw_definition,
      },
      )
    html.gsub(/>\s*\n\s*</, "> <").gsub(/\A\s+/, "").gsub(/\s+\z/, "")
  end
end

Liquid::Template.register_tag("mermaid", MermaidTag)
