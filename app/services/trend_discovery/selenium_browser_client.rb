module TrendDiscovery
  class SeleniumBrowserClient
    STEALTH_SCRIPT = <<~JS.freeze
      Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
      delete navigator.__proto__.webdriver;
      window.chrome = window.chrome || {runtime: {}, loadTimes: () => ({}), csi: () => ({})};
      Object.defineProperty(navigator, 'platform', {get: () => 'Win32'});
      Object.defineProperty(navigator, 'languages', {get: () => ['en-US', 'en']});
      Object.defineProperty(navigator, 'plugins', {get: () => [
        {name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer'},
        {name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai'},
        {name: 'Native Client', filename: 'internal-nacl-plugin'},
      ]});
      Object.defineProperty(navigator, 'mimeTypes', {get: () => [
        {type: 'application/pdf', suffixes: 'pdf'},
        {type: 'application/x-nacl', suffixes: ''},
      ]});
      Object.defineProperty(navigator, 'hardwareConcurrency', {get: () => 8});
      Object.defineProperty(navigator, 'deviceMemory', {get: () => 8});
      Object.defineProperty(navigator, 'maxTouchPoints', {get: () => 0});
      if (navigator.connection) {
        Object.defineProperty(navigator.connection, 'rtt', {get: () => 50});
        Object.defineProperty(navigator.connection, 'downlink', {get: () => 10});
        Object.defineProperty(navigator.connection, 'effectiveType', {get: () => '4g'});
      }
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
      const originalToDataURL = HTMLCanvasElement.prototype.toDataURL;
      HTMLCanvasElement.prototype.toDataURL = function(type) {
        if (type === 'image/png' || type === undefined) {
          const ctx = this.getContext('2d');
          if (ctx) { ctx.fillStyle = 'rgba(0,0,1,0.003)'; ctx.fillRect(0, 0, 1, 1); }
        }
        return originalToDataURL.apply(this, arguments);
      };
      if (navigator.getBattery) {
        navigator.getBattery = () => Promise.resolve({charging: true, chargingTime: 0, dischargingTime: Infinity, level: 1});
      }
    JS

    BOT_CHALLENGE_SELECTORS = [
      { css: "iframe[src*='recaptcha']" },
      { css: "iframe[title*='challenge']" },
      { css: "iframe[src*='sorry']" },
      { css: "form[action*='sorry']" },
      { css: "div#recaptcha" },
    ].freeze

    BOT_PAGE_SIGNALS = [
      "unusual traffic",
      "automated requests",
      "sorry/index",
      "our systems have detected",
      "please show you're not a robot",
    ].freeze

    USER_AGENTS = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    ].freeze

    VIEWPORTS = [
      [1920, 1080], [1600, 900], [1536, 864], [1440, 900],
      [1366, 768], [1280, 720], [1680, 1050], [1600, 1200],
    ].freeze

    NEWS_CARD_SELECTORS = "div.SoaBEf, div.dbsr, div.MjjYud, g-card, article, a.WlydOe".freeze

    DEFAULT_TIMEOUT = ENV.fetch("SELENIUM_PAGE_TIMEOUT", "20").to_i
    DEFAULT_MAX_ATTEMPTS = ENV.fetch("SELENIUM_MAX_ATTEMPTS", "3").to_i
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

          warm_up_session(driver, url)

          random_pre_delay
          driver.navigate.to(url)

          wait = Selenium::WebDriver::Wait.new(timeout: @timeout)
          wait.until { driver.page_source&.include?("<body") }

          if bot_detected?(driver)
            Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Bot detected on attempt #{attempt + 1} for #{url}")
            raise BotDetectedError, "Bot challenge or captcha detected"
          end

          dismiss_consent(driver)
          ensure_news_mode(driver, url) if news_mode
          perform_human_interaction(driver)

          if bot_detected?(driver)
            Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Bot detected after interaction on attempt #{attempt + 1}")
            raise BotDetectedError, "Bot challenge appeared after interaction"
          end

          result = yield(driver)
          return result
        rescue Selenium::WebDriver::Error::SessionNotCreatedError => e
          Rails.logger.error("TrendDiscovery::SeleniumBrowserClient: Session creation failed on attempt #{attempt + 1}: #{e.message}")
          break
        rescue BotDetectedError => e
          Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: #{e.message} (attempt #{attempt + 1}/#{@max_attempts})")
        rescue StandardError => e
          Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Page load failed on attempt #{attempt + 1} for #{url}: #{e.message}")
        ensure
          safe_quit(driver)
        end

        backoff = (2**attempt) + rand(1.0..3.0)
        Rails.logger.info("TrendDiscovery::SeleniumBrowserClient: Backing off #{backoff.round(1)}s before retry")
        sleep(backoff)
      end

      nil
    end

    def create_driver
      viewport = VIEWPORTS.sample
      user_agent = ENV["SELENIUM_USER_AGENT"].presence || USER_AGENTS.sample

      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument("--headless=new")
      options.add_argument("--window-size=#{viewport[0]},#{viewport[1]}")
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
      options.add_argument("--disable-gpu")
      options.add_argument("--disable-background-networking")
      options.add_argument("--disable-background-timer-throttling")
      options.add_argument("--disable-renderer-backgrounding")
      options.add_argument("--disable-features=Translate,OptimizationHints,MediaRouter,AutofillServerCommunication")
      options.add_argument("--lang=en-US")
      options.add_argument("--disable-blink-features=AutomationControlled")
      options.add_argument("--user-agent=#{user_agent}")
      options.add_argument("--disable-extensions")
      options.add_argument("--disable-infobars")
      options.add_argument("--disable-popup-blocking")

      options.add_preference("credentials_enable_service", false)
      options.add_preference("profile.password_manager_enabled", false)

      driver = Selenium::WebDriver.for(
        :remote,
        url: @remote_url,
        options: options,
        )

      apply_stealth(driver)
      driver
    end

    def apply_stealth(driver)
      driver.navigate.to("about:blank")
      driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: STEALTH_SCRIPT)
      driver.execute_script(STEALTH_SCRIPT)
    rescue StandardError => e
      Rails.logger.debug("TrendDiscovery::SeleniumBrowserClient: Unable to apply stealth: #{e.message}")
    end

    def warm_up_session(driver, target_url)
      host = URI.parse(target_url).host rescue nil
      return unless host&.include?("google")

      driver.navigate.to("https://www.google.com")
      interaction_sleep
      dismiss_consent(driver)
      interaction_sleep
    rescue StandardError => e
      Rails.logger.debug("TrendDiscovery::SeleniumBrowserClient: Warm-up failed: #{e.message}")
    end

    def bot_detected?(driver)
      BOT_CHALLENGE_SELECTORS.each do |selector|
        elements = selector[:css] ? driver.find_elements(css: selector[:css]) : driver.find_elements(xpath: selector[:xpath])
        if elements.any?
          Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Bot signal — matched selector #{selector.inspect}")
          return true
        end
      end

      page_text = driver.page_source.to_s.downcase
      BOT_PAGE_SIGNALS.each do |signal|
        if page_text.include?(signal)
          Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Bot signal — page contains '#{signal}'")
          return true
        end
      end

      false
    rescue StandardError
      false
    end

    def random_pre_delay
      sleep(rand(0.5..2.0))
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
        driver.navigate.to("#{search_url}#{separator}tbm=nws")
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

    def perform_human_interaction(driver)
      simulate_mouse_movement(driver)
      perform_light_interaction(driver)
      random_pause
    end

    def simulate_mouse_movement(driver)
      driver.execute_script(<<~JS)
        (function() {
          const events = ['mousemove', 'mouseover'];
          const body = document.body;
          for (let i = 0; i < 3 + Math.floor(Math.random() * 4); i++) {
            const x = Math.floor(Math.random() * window.innerWidth);
            const y = Math.floor(Math.random() * window.innerHeight);
            events.forEach(type => {
              body.dispatchEvent(new MouseEvent(type, {
                clientX: x, clientY: y, bubbles: true
              }));
            });
          }
        })();
      JS
    rescue StandardError
      # non-critical
    end

    def random_pause
      sleep(rand(0.3..1.2))
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

    class BotDetectedError < StandardError; end

    def interaction_sleep
      sleep((@interaction_delay_ms + rand(300)) / 1000.0)
    end

    def safe_quit(driver)
      return unless driver

      driver.quit
    rescue StandardError
      # ignore
    end
  end
end
