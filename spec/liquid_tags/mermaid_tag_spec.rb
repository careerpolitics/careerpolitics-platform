require "rails_helper"

RSpec.describe MermaidTag, type: :liquid_tag do
  def generate_mermaid_liquid(definition)
    Liquid::Template.register_tag("mermaid", described_class)
    Liquid::Template.parse("{% mermaid %}#{definition}{% endmermaid %}")
  end

  describe "#render" do
    it "renders the definition inside a mermaid-container div" do
      rendered = generate_mermaid_liquid("graph TD\n  A --> B").render
      expect(rendered).to include("mermaid-container")
    end

    it "renders a pre.mermaid element with the raw definition" do
      rendered = generate_mermaid_liquid("graph TD\n  A --> B").render
      expect(rendered).to include('<pre class="mermaid">')
      expect(rendered).to include("graph TD")
    end

    it "HTML-escapes the definition to prevent XSS" do
      rendered = generate_mermaid_liquid('<script>alert("xss")</script>').render
      expect(rendered).not_to include("<script>alert")
      expect(rendered).to include("&lt;script&gt;")
    end

    it "collapses whitespace to survive Redcarpet second pass" do
      rendered = generate_mermaid_liquid("graph TD\n  A --> B").render
      expect(rendered).not_to match(/>\s*\n\s*</)
    end
  end

  describe ".script" do
    it "returns a script tag that loads mermaid from CDN" do
      expect(described_class.script).to include("mermaid")
      expect(described_class.script).to include("cdn.jsdelivr.net")
    end
  end
end
