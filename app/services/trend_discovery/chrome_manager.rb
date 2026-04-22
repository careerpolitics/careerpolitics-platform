module TrendDiscovery
  class ChromeManager
    # When SELENIUM_REMOTE_URL is set (e.g. K8s service), skip Docker entirely.
    # When unset, fall back to ephemeral Docker container management (local dev).
    REMOTE_URL = ENV.fetch("SELENIUM_REMOTE_URL", nil)

    CHROME_IMAGE = ENV.fetch("SELENIUM_CHROME_IMAGE", "selenium/standalone-chrome:latest")
    SHM_SIZE = begin
                 raw = ENV.fetch("SELENIUM_SHM_SIZE", "2g").to_s.strip.downcase
                 value, unit = raw.match(/\A(\d+)\s*(g|m)?\z/)&.captures || [2, "g"]
                 bytes = value.to_i * (unit == "m" ? 1024 * 1024 : 1024 * 1024 * 1024)
                 bytes.clamp(256 * 1024 * 1024, 8 * 1024 * 1024 * 1024) # 256MB..8GB
               end
    SHM_SIZE = ENV.fetch("SELENIUM_SHM_SIZE", "2g").to_i * 1024 * 1024 * 1024
    NETWORK = ENV.fetch("SELENIUM_NETWORK", nil)
    CONTAINER_TIMEOUT = ENV.fetch("SELENIUM_CONTAINER_TIMEOUT", "120").to_i
    READY_POLL_INTERVAL = 2
    READY_MAX_WAIT = 60

    attr_reader :remote_url

    def initialize
      @container = nil
      @remote_url = nil
      @static_mode = REMOTE_URL.present?
    end

    def start!
      if @static_mode
        @remote_url = REMOTE_URL
        Rails.logger.info("TrendDiscovery::ChromeManager: Using static Selenium URL #{@remote_url}")
        wait_until_ready!
        return @remote_url
      end

      start_docker_container!
    end

    def stop!
      if @static_mode
        Rails.logger.debug("TrendDiscovery::ChromeManager: Static mode — nothing to stop")
        @remote_url = nil
        return
      end

      stop_docker_container!
    end

    private

    # --- Shared ---

    def wait_until_ready!
      status_url = @remote_url.sub(%r{/wd/hub\z}, "/wd/hub/status")
      deadline = Time.current + READY_MAX_WAIT

      while Time.current < deadline
        begin
          response = HTTParty.get(status_url, timeout: 3)
          if response.success? && response.parsed_response.dig("value", "ready")
            return true
          end
        rescue StandardError
          # Not yet accepting connections
        end

        sleep(READY_POLL_INTERVAL)
      end

      raise "Selenium at #{@remote_url} did not become ready within #{READY_MAX_WAIT}s"
    end

    # --- Docker container mode (local dev) ---

    def start_docker_container!
      require "docker-api"

      reap_orphans

      Rails.logger.info("TrendDiscovery::ChromeManager: Creating Chrome container from #{CHROME_IMAGE}")

      container_config = {
        "Image" => CHROME_IMAGE,
        "Env" => [
          "SE_NODE_MAX_SESSIONS=1",
          "SE_SESSION_REQUEST_TIMEOUT=120",
          "SE_NODE_SESSION_TIMEOUT=120",
        ],
        "HostConfig" => {
          "ShmSize" => SHM_SIZE,
        },
        "Labels" => {
          "careerpolitics.trending" => "true",
          "careerpolitics.created_at" => Time.current.to_i.to_s,
        },
      }

      if NETWORK.present?
        container_config["HostConfig"]["NetworkMode"] = NETWORK
      else
        container_config["ExposedPorts"] = { "4444/tcp" => {} }
        container_config["HostConfig"]["PortBindings"] = {
          "4444/tcp" => [{ "HostPort" => "0" }],
        }
      end

      @container = Docker::Container.create(container_config)
      @container.start

      @remote_url = resolve_remote_url
      wait_until_ready!

      Rails.logger.info("TrendDiscovery::ChromeManager: Chrome container #{@container.id[0..11]} ready at #{@remote_url}")
      @remote_url
    end

    def stop_docker_container!
      return unless @container

      container_id = @container.id[0..11]
      Rails.logger.info("TrendDiscovery::ChromeManager: Stopping Chrome container #{container_id}")

      begin
        @container.stop(t: 5)
      rescue Docker::Error::NotFoundError
        Rails.logger.debug("TrendDiscovery::ChromeManager: Container #{container_id} already stopped")
      rescue StandardError => e
        Rails.logger.warn("TrendDiscovery::ChromeManager: Error stopping container #{container_id}: #{e.message}")
      end

      begin
        @container.remove(force: true)
      rescue Docker::Error::NotFoundError
        Rails.logger.debug("TrendDiscovery::ChromeManager: Container #{container_id} already removed")
      rescue StandardError => e
        Rails.logger.warn("TrendDiscovery::ChromeManager: Error removing container #{container_id}: #{e.message}")
      end

      @container = nil
      @remote_url = nil
    end

    def resolve_remote_url
      if NETWORK.present?
        container_info = @container.json
        ip = container_info.dig("NetworkSettings", "Networks", NETWORK, "IPAddress")
        raise "Cannot determine container IP on network #{NETWORK}" if ip.blank?

        "http://#{ip}:4444/wd/hub"
      else
        container_info = @container.json
        host_port = container_info.dig("NetworkSettings", "Ports", "4444/tcp", 0, "HostPort")
        raise "Cannot determine host port for Chrome container" if host_port.blank?

        "http://localhost:#{host_port}/wd/hub"
      end
    end

    def reap_orphans
      cutoff = Time.current.to_i - CONTAINER_TIMEOUT
      Docker::Container.all(all: true, filters: { label: ["careerpolitics.trending=true"] }.to_json).each do |container|
        created_at = container.json.dig("Config", "Labels", "careerpolitics.created_at").to_i
        next if created_at > cutoff

        Rails.logger.warn("TrendDiscovery::ChromeManager: Reaping orphan container #{container.id[0..11]}")
        begin
          container.stop(t: 2)
          container.remove(force: true)
        rescue StandardError => e
          Rails.logger.warn("TrendDiscovery::ChromeManager: Failed to reap #{container.id[0..11]}: #{e.message}")
        end
      end
    rescue StandardError => e
      Rails.logger.warn("TrendDiscovery::ChromeManager: Orphan reaping failed: #{e.message}")
    end
  end
end
