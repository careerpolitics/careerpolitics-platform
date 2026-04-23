module TrendDiscovery
  class SeleniumBrowserClient
    STEALTH_SCRIPT_TEMPLATE = <<~JS.freeze
      Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
      delete navigator.__proto__.webdriver;
      window.chrome = window.chrome || {runtime: {}, loadTimes: () => ({}), csi: () => ({})};
      Object.defineProperty(navigator, 'platform', {get: () => '%<platform>s'});
      Object.defineProperty(navigator, 'languages', {get: () => %<languages>s});
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

    BOT_CHALLENGE_SELECTOR = "iframe[src*='recaptcha'], iframe[title*='challenge'], iframe[src*='sorry']".freeze

    BOT_TEXT_SIGNALS = [
      "unusual traffic",
      "verify you are human",
      "i'm not a robot",
      "complete the captcha",
      "g-recaptcha",
    ].freeze

    BOT_TITLE_SIGNALS = [
      "unusual traffic",
      "sorry",
    ].freeze

    BROWSER_PROFILES = [
      {
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
        platform: "Win32",
        languages: ["en-US", "en"],
      },
      {
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
        platform: "Win32",
        languages: ["en-US", "en"],
      },
      {
        user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
        platform: "MacIntel",
        languages: ["en-US", "en"],
      },
      {
        user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
        platform: "MacIntel",
        languages: ["en-US", "en"],
      },
      {
        user_agent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
        platform: "Linux x86_64",
        languages: ["en-US", "en"],
      },
      {
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
        platform: "Win32",
        languages: ["en-US", "en"],
      },
    ].freeze

    VIEWPORTS = [
      [1920, 1080], [1600, 900], [1536, 864], [1440, 900],
      [1366, 768], [1280, 720], [1680, 1050], [1600, 1200],
    ].freeze

    NEWS_CARD_SELECTORS = "div.SoaBEf, div.dbsr, div.MjjYud, g-card, article, a.WlydOe".freeze

    DEFAULT_TIMEOUT = ENV.fetch("SELENIUM_PAGE_TIMEOUT", "20").to_i
    DEFAULT_MAX_ATTEMPTS = ENV.fetch("SELENIUM_MAX_ATTEMPTS", "3").to_i
    DEFAULT_INTERACTION_DELAY = ENV.fetch("SELENIUM_INTERACTION_DELAY_MS", "750").to_i
    PROXY_POOL = ENV.fetch("SELENIUM_PROXY_POOL", "").split(",").map(&:strip).reject(&:blank?).freeze
    SESSION_RETRY_BACKOFF_MS = ENV.fetch("SELENIUM_SESSION_RETRY_BACKOFF_MS", "2000").to_i

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
      proxies = PROXY_POOL
      @max_attempts.times do |attempt|
        proxy = proxies.any? ? proxies[attempt % proxies.length] : nil
        driver = nil
        begin
          driver = create_driver(proxy: proxy)
          driver.navigate.to(url)

          wait = Selenium::WebDriver::Wait.new(timeout: @timeout)
          wait.until { driver.page_source&.include?("<body") }

          dismiss_consent(driver)
          ensure_news_mode(driver, url) if news_mode
          perform_light_interaction(driver)

          if news_mode && bot_detected?(driver)
            Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Bot detected on attempt #{attempt + 1} for #{url}")
            raise BotDetectedError, "Bot challenge or captcha detected"
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

        backoff_ms = SESSION_RETRY_BACKOFF_MS + rand(150)
        Rails.logger.info("TrendDiscovery::SeleniumBrowserClient: Backing off #{backoff_ms}ms before retry")
        sleep(backoff_ms / 1000.0)
      end

      nil
    end

    def create_driver(proxy: nil)
      viewport = VIEWPORTS.sample
      profile = random_browser_profile

      options = Selenium::WebDriver::Chrome::Options.new
      options.page_load_strategy = :eager
      options.add_argument("--headless=new")
      options.add_argument("--window-size=#{viewport[0]},#{viewport[1]}")
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
      options.add_argument("--disable-gpu")
      options.add_argument("--disable-extensions")
      options.add_argument("--mute-audio")
      options.add_argument("--disable-features=Translate,OptimizationHints,MediaRouter")
      options.add_argument("--lang=#{profile[:languages].first}")
      options.add_argument("--disable-blink-features=AutomationControlled")
      options.add_argument("--user-agent=#{profile[:user_agent]}")
      options.add_argument("--proxy-server=http://#{proxy}") if proxy.present?

      options.add_preference("intl.accept_languages", profile[:languages].join(","))
      options.add_preference("credentials_enable_service", false)
      options.add_preference("profile.password_manager_enabled", false)

      driver = Selenium::WebDriver.for(
        :remote,
        url: @remote_url,
        options: options,
        )

      apply_stealth(driver, profile: profile)
      driver
    end

    def apply_stealth(driver, profile:)
      stealth_script = build_stealth_script(profile)
      driver.navigate.to("data:,")
      driver.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: stealth_script)
      driver.execute_script(stealth_script)
    rescue StandardError => e
      Rails.logger.debug("TrendDiscovery::SeleniumBrowserClient: Unable to apply stealth: #{e.message}")
    end

    def build_stealth_script(profile)
      format(
        STEALTH_SCRIPT_TEMPLATE,
        platform: profile[:platform],
        languages: profile[:languages].to_json,
      )
    end

    def random_browser_profile
      profile = BROWSER_PROFILES.sample.deep_dup
      user_agent_override = ENV["SELENIUM_USER_AGENT"].presence
      profile[:user_agent] = user_agent_override if user_agent_override
      profile
    end

    def bot_detected?(driver)
      has_challenge_frame = driver.find_elements(css: BOT_CHALLENGE_SELECTOR).any?
      has_news_cards = driver.find_elements(css: NEWS_CARD_SELECTORS).any?

      title = driver.title.to_s.downcase
      body = driver.page_source.to_s.downcase

      challenge_text = BOT_TITLE_SIGNALS.any? { |s| title.include?(s) } ||
                       BOT_TEXT_SIGNALS.any? { |s| body.include?(s) }

      is_bot = (has_challenge_frame || challenge_text) && !has_news_cards

      if is_bot
        Rails.logger.warn("TrendDiscovery::SeleniumBrowserClient: Bot signal — challenge_frame=#{has_challenge_frame} challenge_text=#{challenge_text}")
      end

      is_bot
    rescue StandardError
      false
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
