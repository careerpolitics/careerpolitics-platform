module MockExams
  class SvgSanitizer
    ALLOWED_ELEMENTS = %w[
      svg rect circle ellipse line polyline polygon path
      text tspan g defs use marker pattern
    ].freeze

    ALLOWED_ATTRIBUTES = %w[
      viewBox width height x y x1 y1 x2 y2
      cx cy r rx ry
      fill stroke stroke-width stroke-dasharray stroke-linecap stroke-linejoin
      transform d points
      font-size font-family font-weight text-anchor dominant-baseline
      opacity fill-opacity stroke-opacity
      id class
      dx dy rotate
      markerWidth markerHeight refX refY orient
      patternUnits patternTransform
    ].freeze

    ALLOWED_STYLE_PROPERTIES = %w[
      fill stroke stroke-width opacity
      font-size font-family font-weight text-anchor
      transform
    ].freeze

    DANGEROUS_ELEMENTS = %w[
      script foreignObject iframe object embed
      animate animateMotion animateTransform set
    ].freeze

    def initialize(svg_string)
      @svg_string = svg_string.to_s.strip
    end

    def call
      return nil if @svg_string.blank?

      doc = Nokogiri::XML::DocumentFragment.parse(@svg_string)
      sanitize_node(doc)
      result = doc.to_html

      return nil if result.blank? || !result.include?("<svg")

      result
    end

    def self.sanitize(svg_string)
      new(svg_string).call
    end

    def self.sanitize_options(options)
      return options unless options.is_a?(Array)

      options.map do |opt|
        next opt unless opt.is_a?(Hash) && opt["svg"].present?

        opt.merge("svg" => sanitize(opt["svg"]))
      end
    end

    private

    def sanitize_node(node)
      node.children.each do |child|
        case child.type
        when Nokogiri::XML::Node::ELEMENT_NODE
          if dangerous_element?(child.name)
            child.remove
            next
          end

          unless allowed_element?(child.name)
            child.remove
            next
          end

          sanitize_attributes(child)
          sanitize_node(child)
        when Nokogiri::XML::Node::TEXT_NODE
          # Text nodes are safe
        when Nokogiri::XML::Node::CDATA_SECTION_NODE
          child.remove
        when Nokogiri::XML::Node::COMMENT_NODE
          child.remove
        else
          child.remove
        end
      end
    end

    def sanitize_attributes(element)
      element.attributes.each do |name, attr|
        # Remove all event handlers
        if name.start_with?("on")
          element.remove_attribute(name)
          next
        end

        # Remove xlink:href with external references
        if name == "href" || name == "xlink:href"
          value = attr.value.to_s.strip
          unless value.start_with?("#")
            element.remove_attribute(name)
          end
          next
        end

        # Remove non-whitelisted attributes
        unless ALLOWED_ATTRIBUTES.include?(name)
          if name == "style"
            element["style"] = sanitize_style(attr.value)
          else
            element.remove_attribute(name)
          end
          next
        end

        # Sanitize attribute values — no javascript: URIs
        if attr.value.to_s.downcase.include?("javascript:")
          element.remove_attribute(name)
        end
      end
    end

    def sanitize_style(style_string)
      return "" if style_string.blank?

      safe_declarations = []
      style_string.split(";").each do |declaration|
        prop, value = declaration.split(":", 2).map(&:strip)
        next if prop.blank? || value.blank?

        prop_clean = prop.downcase.strip
        next unless ALLOWED_STYLE_PROPERTIES.include?(prop_clean)

        # Block url() and expression() in values
        value_clean = value.downcase
        next if value_clean.include?("url(") || value_clean.include?("expression(") || value_clean.include?("javascript:")

        safe_declarations << "#{prop_clean}: #{value}"
      end

      safe_declarations.join("; ")
    end

    def allowed_element?(name)
      ALLOWED_ELEMENTS.include?(name.downcase)
    end

    def dangerous_element?(name)
      DANGEROUS_ELEMENTS.include?(name.downcase)
    end
  end
end
