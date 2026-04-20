module TrendDiscovery
  class SeleniumBrowserClient
    STEALTH_SCRIPT = <<~JS.freeze
      Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
      window.chrome = window.chrome || {runtime: {}};
      Object.defineProperty(navigator, 'platform', {get: () => 'Win32'});
      Object.defineProperty(navigator, 'languages', {get: () => ['en-US', 'en']});
      Object.defineProperty(navigator, 'plugins', {get: () => [1, 2, 3, 4, 5]});
      Object.defineProperty(navigator, 'hardwareConcurrency', {get: () => 8});
      Object.defineProperty(navigator, 'deviceMemory', {get: () => 8});
      const getParameter = WebGLRenderingContext.prototype.getParameter;
      WebGLRenderingContext.prototype.getParameter = function(parameter) {
        if (parameter === 37445) return 'Intel Inc.';
        if (parameter === 37446) return 'Intel Iris OpenGL Engine';
        return getParameter.call(this, parameter);
      };
      const originalQuery = window.navigator.permissions && window.navigator.permissions.query;
      if (originalQuery) {
        window.navigator.permissions.query = (parameters) => (
          parameters && parameters.name === 'notifications'
            ? Promise.resolve({ state: Notification.permission })
            : originalQuery(parameters)
        );
      }
    JS

    BOT_CHALLENGE_SELECTORS = [
      { css: "iframe[src*='recaptcha']" },
      { css: "iframe[title*='challenge']" },
      { css: "iframe[src*='sorry']" },
    ].freeze

    NEWS_CARD_SELECTORS = "div.SoaBEf, div.dbsr, div.MjjYud, g-card, article, a.WlydOe".freeze

    DEFAULT_TIMEOUT = ENV.fetch("SELENIUM_PAGE_TIMEOUT", "20").to_i
    DEFAULT_MAX_ATTEMPTS = ENV.fetch("SELENIUM_MAX_ATTEMPTS", "2").to_i
    DEFAULT_INTERACTION_DELAY = ENV.fetch("SELENIUM_INTERACTION_DELAY_MS", "750").to_i

    def initialize(remote_url:, timeout: DEFAULT_TIMEOUT, max_attempts: DEFAULT_MAX_ATTEMPTS, interaction_delay_ms: DEFAULT_INTERACTION_DELAY)
      @remote_url = remote_url
      @timeout = timeout
      @max_attempts = [1, max_attempts].max
      @interaction_delay_ms = interaction_delay_ms
    end

    def fetch_page(url, news_mode: false)
      load_page(url, news_mode: news_mode) { |driver| driver.page_source }
    end

    def fetch_trend_titles(url, max_trends:)
      load_page(url, news_mode: false) do |driver|
        extract_trend_titles(driver, max_trends)
      end
    end

    private

    def load_page(url, news_mode: false)
      @max_attempts.times do |attempt|
        driver = nil
        begin
          driver = create_driver
          driver.navigate.to(url)

          wait = Selenium::WebDriver::Wait.new(timeout: @timeout)
          wait.until { driver.page_source&.include?("<body") }

          dismiss_consent(driver)
          ensure_news_mode(driver, url) if news_mode
          perform_light_interaction(driver)

          result = yield(driver)
          return result
        rescue Selenium::WebDriver::Error::SessionNotCreatedError => e
          Rails.logger.error("TrendDiscovery::SeleniumBrowserClient: Session creation failed on attempt #{attempt + 1}: #{e.message}")
          break
        rescue StandardError => e
          Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Page load failed on attempt #{attempt + 1} for #{url}: #{e.message}")
        ensure
          safe_quit(driver)
        end

        sleep(2 + rand(0.5))
      end

      nil
    end

    def create_driver
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument("--headless=new")
      options.add_argument("--window-size=1600,1200")
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
      options.add_argument("--disable-gpu")
      options.add_argument("--disable-background-networking")
      options.add_argument("--disable-background-timer-throttling")
      options.add_argument("--disable-renderer-backgrounding")
      options.add_argument("--disable-features=Translate,OptimizationHints,MediaRouter")
      options.add_argument("--lang=en-US")
      options.add_argument("--disable-blink-features=AutomationControlled")

      user_agent = ENV["SELENIUM_USER_AGENT"]
      options.add_argument("--user-agent=#{user_agent}") if user_agent.present?

      driver = Selenium::WebDriver.for(
        :remote,
        url: @remote_url,
        options: options,
        )

      apply_stealth(driver)
      driver
    end

    def apply_stealth(driver)
      driver.navigate.to("data:,")
      driver.execute_script(STEALTH_SCRIPT)
    rescue StandardError => e
      Rails.logger.debug("TrendDiscovery::SeleniumBrowserClient: Unable to apply stealth: #{e.message}")
    end

    def dismiss_consent(driver)
      selectors = [
        { css: "button#L2AGLb" },
        { css: "button[aria-label*='Accept']" },
        { xpath: "//button[contains(., 'Accept all') or contains(., 'I agree')]" },
      ]

      selectors.each do |selector|
        begin
          elements = selector[:css] ? driver.find_elements(css: selector[:css]) : driver.find_elements(xpath: selector[:xpath])
          next if elements.empty?

          elements.first.click
          interaction_sleep
          return
        rescue StandardError
          next
        end
      end
    end

    def ensure_news_mode(driver, search_url)
      news_cards = driver.find_elements(css: NEWS_CARD_SELECTORS)
      return if news_cards.any?

      news_tabs = driver.find_elements(css: "a[href*='tbm=nws']")
      if news_tabs.any?
        news_tabs.first.click
        interaction_sleep
        return
      end

      unless search_url.include?("tbm=nws")
        separator = search_url.include?("?") ? "&" : "?"
        driver.navigate.to("#{search_url}#{separator}tbm=nws&udm=14")
        interaction_sleep
      end
    rescue StandardError => e
      Rails.logger.debug("TrendDiscovery::SeleniumBrowserClient: Unable to force news mode: #{e.message}")
    end

    def perform_light_interaction(driver)
      driver.execute_script("window.scrollTo(0, document.body.scrollHeight * 0.35);")
      interaction_sleep
      driver.execute_script("window.scrollTo(0, document.body.scrollHeight * 0.7);")
      interaction_sleep
    rescue StandardError => e
      Rails.logger.debug("TrendDiscovery::SeleniumBrowserClient: Light interaction failed: #{e.message}")
    end

    def extract_trend_titles(driver, max_trends)
      desired = [1, max_trends].max
      6.times do
        titles = run_trend_extraction_script(driver, desired)
        return titles.first(desired) if titles.any?

        perform_light_interaction(driver)
        interaction_sleep
      end
      []
    end

    def run_trend_extraction_script(driver, max_trends)
      result = driver.execute_script(<<~JS, max_trends)
        const maxTrends = arguments[0];
        const rowSelectors = ['table tbody tr', 'tbody tr', '[role="row"]', '[data-row-id]'];
        const titleSelectors = ['[data-term]', '.mZ3RIc', '.QNIh4d', 'a[title]'];
        const noisePatterns = [
          /^trending_up$/i,
          /^active$/i,
          /^\\d+(?:[.,]\\d+)?(?:[KMB])?\\+?\\s*searches$/i,
          /^\\d+\\s*(?:sec(?:ond)?s?|min(?:ute)?s?|hr|hour|day|week|month)s?\\s+ago$/i,
          /^\\d{1,2}:\\d{2}\\s*(?:am|pm)$/i
        ];
        const seen = new Set();
        const visible = (el) => {
          if (!el) return false;
          const style = window.getComputedStyle(el);
          const rect = el.getBoundingClientRect();
          return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
        };
        const clean = (value) => (value || '')
          .replace(/\\b(?:trending_up|arrow_upward|timelapse)\\b/gi, ' ')
          .replace(/\\bactive\\b/gi, ' ')
          .replace(/\\b\\d+(?:[.,]\\d+)?(?:[KMB])?\\+?\\s*searches\\b/gi, ' ')
          .replace(/\\b(?:\\d+\\s*(?:sec(?:ond)?s?|min(?:ute)?s?|hr|hour|day|week|month)s?\\s+ago|\\d{1,2}:\\d{2}\\s*(?:am|pm))\\b/gi, ' ')
          .replace(/\\s+/g, ' ')
          .trim();
        const isNoise = (value) => !value || noisePatterns.some((pattern) => pattern.test(value));
        const pushCandidate = (output, candidate) => {
          const cleaned = clean(candidate);
          if (cleaned.length < 3 || cleaned.length > 120 || isNoise(cleaned)) return;
          const slug = cleaned.toLowerCase();
          if (seen.has(slug)) return;
          seen.add(slug);
          output.push(cleaned);
        };
        const rows = [];
        for (const selector of rowSelectors) {
          const found = Array.from(document.querySelectorAll(selector)).filter(visible);
          if (found.length) {
            rows.push(...found);
            break;
          }
        }
        const output = [];
        for (const row of rows) {
          let title = '';
          for (const selector of titleSelectors) {
            const el = Array.from(row.querySelectorAll(selector)).find(visible);
            if (!el) continue;
            title = el.getAttribute('data-term') || el.getAttribute('title') || el.innerText || '';
            title = clean(title);
            if (!isNoise(title)) break;
          }
          pushCandidate(output, title);
          if (output.length >= maxTrends) return output;
        }
        if (output.length) return output;
        for (const selector of titleSelectors) {
          const elements = Array.from(document.querySelectorAll(selector)).filter(visible);
          for (const el of elements) {
            pushCandidate(output, el.getAttribute('data-term') || el.getAttribute('title') || el.innerText || '');
            if (output.length >= maxTrends) return output;
          }
        }
        return output;
      JS

      return [] unless result.is_a?(Array)

      result.select { |v| v.is_a?(String) && v.strip.present? }.map(&:strip)
    end

    def interaction_sleep
      sleep((@interaction_delay_ms + rand(150)) / 1000.0)
    end

    def safe_quit(driver)
      return unless driver

      driver.quit
    rescue StandardError
      # ignore
    end
  end
end
