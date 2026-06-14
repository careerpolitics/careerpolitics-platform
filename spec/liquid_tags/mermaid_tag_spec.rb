require "rails_helper"

RSpec.describe MermaidTag, type: :liquid_tag do
  def generate_mermaid_liquid(definition)
    Liquid::Template.register_tag("mermaid", described_class)
    Liquid::Template.parse("{% mermaid %}#{definition}{% endmermaid %}")
  end

  describe "#render" do
    context "when mermaid-cli is available" do
      let(:sample_svg) do
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="50" height="50"/></svg>'
      end

      before do
        allow_any_instance_of(described_class).to receive(:render_mermaid_svg).and_return(sample_svg)
      end

      it "renders SVG content inside a mermaid-container div" do
        rendered = generate_mermaid_liquid("graph TD\n  A --> B").render
        expect(rendered).to include("mermaid-container")
        expect(rendered).to include("<svg")
      end

      it "includes the raw definition as a data attribute" do
        rendered = generate_mermaid_liquid("graph TD\n  A --> B").render
        expect(rendered).to include("data-mermaid-source")
      end

      it "collapses whitespace to survive Redcarpet second pass" do
        rendered = generate_mermaid_liquid("graph TD\n  A --> B").render
        expect(rendered).not_to match(/>\s*\n\s*</)
      end
    end

    context "when mermaid-cli is not available" do
      before do
        allow_any_instance_of(described_class).to receive(:find_mmdc).and_return(nil)
      end

      it "renders a fallback code block with error message" do
        rendered = generate_mermaid_liquid("graph TD\n  A --> B").render
        expect(rendered).to include("mermaid-fallback")
        expect(rendered).to include("mmdc")
      end
    end
  end

  describe "#find_mmdc" do
    it "returns nil when mmdc is not installed" do
      tag_instance = described_class.allocate
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)
      result = tag_instance.send(:find_mmdc)
      expect(result).to be_nil
    end
  end
end
