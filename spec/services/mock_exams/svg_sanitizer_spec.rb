require "rails_helper"

RSpec.describe MockExams::SvgSanitizer do
  describe ".sanitize" do
    it "passes through valid SVG" do
      svg = '<svg viewBox="0 0 200 200" width="200" height="200"><circle cx="100" cy="100" r="50" fill="black"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).to include("<circle")
      expect(result).to include("cx=")
    end

    it "returns nil for blank input" do
      expect(described_class.sanitize("")).to be_nil
      expect(described_class.sanitize(nil)).to be_nil
    end

    it "returns nil for non-SVG content" do
      expect(described_class.sanitize("<p>hello</p>")).to be_nil
    end

    it "strips script tags" do
      svg = '<svg viewBox="0 0 200 200"><script>alert("xss")</script><rect width="100" height="100"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("<script")
      expect(result).not_to include("alert")
      expect(result).to include("<rect")
    end

    it "strips foreignObject elements" do
      svg = '<svg viewBox="0 0 200 200"><foreignObject><div>hack</div></foreignObject><circle r="50"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("foreignObject")
      expect(result).not_to include("hack")
    end

    it "strips event handler attributes" do
      svg = '<svg viewBox="0 0 200 200"><rect width="100" height="100" onclick="alert(1)" onload="evil()"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("onclick")
      expect(result).not_to include("onload")
      expect(result).to include("<rect")
    end

    it "strips javascript: URIs" do
      svg = '<svg viewBox="0 0 200 200"><rect width="100" height="100" fill="javascript:alert(1)"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("javascript:")
    end

    it "strips external xlink:href" do
      svg = '<svg viewBox="0 0 200 200"><use xlink:href="http://evil.com/inject.svg"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("evil.com")
    end

    it "allows internal xlink:href references" do
      svg = '<svg viewBox="0 0 200 200"><defs><circle id="c" r="10"/></defs><use href="#c"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).to include("#c")
    end

    it "strips disallowed elements" do
      svg = '<svg viewBox="0 0 200 200"><iframe src="evil.com"/><rect width="100" height="100"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("iframe")
      expect(result).to include("<rect")
    end

    it "strips animate elements" do
      svg = '<svg viewBox="0 0 200 200"><rect width="100" height="100"><animate attributeName="x" from="0" to="100"/></rect></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("<animate")
    end

    it "sanitizes style attributes" do
      svg = '<svg viewBox="0 0 200 200"><rect width="100" height="100" style="fill: red; cursor: pointer; expression(evil)"/></svg>'
      result = described_class.sanitize(svg)
      expect(result).to include("fill: red")
      expect(result).not_to include("expression")
      expect(result).not_to include("cursor")
    end

    it "strips CDATA sections" do
      svg = '<svg viewBox="0 0 200 200"><rect width="100" height="100"/><![CDATA[evil content]]></svg>'
      result = described_class.sanitize(svg)
      expect(result).not_to include("CDATA")
      expect(result).not_to include("evil content")
    end

    it "preserves nested g elements" do
      svg = '<svg viewBox="0 0 200 200"><g transform="translate(10,10)"><rect width="50" height="50"/></g></svg>'
      result = described_class.sanitize(svg)
      expect(result).to include("<g")
      expect(result).to include("translate")
    end

    it "preserves text elements" do
      svg = '<svg viewBox="0 0 200 200"><text x="50" y="50" font-size="14">Hello</text></svg>'
      result = described_class.sanitize(svg)
      expect(result).to include("<text")
      expect(result).to include("Hello")
    end
  end

  describe ".sanitize_options" do
    it "sanitizes svg field in each option" do
      options = [
        { "key" => "A", "text" => "Option A", "svg" => '<svg viewBox="0 0 100 100"><circle r="20"/></svg>' },
        { "key" => "B", "text" => "Option B", "svg" => '<svg viewBox="0 0 100 100"><script>bad</script><rect width="20" height="20"/></svg>' },
        { "key" => "C", "text" => "Option C" },
        { "key" => "D", "text" => "Option D", "svg" => nil },
      ]

      result = described_class.sanitize_options(options)

      expect(result[0]["svg"]).to include("<circle")
      expect(result[1]["svg"]).not_to include("<script")
      expect(result[1]["svg"]).to include("<rect")
      expect(result[2]).not_to have_key("svg")
      expect(result[3]["svg"]).to be_nil
    end

    it "returns input unchanged if not an array" do
      expect(described_class.sanitize_options(nil)).to be_nil
      expect(described_class.sanitize_options("string")).to eq("string")
    end
  end
end
