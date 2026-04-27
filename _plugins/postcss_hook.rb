# frozen_string_literal: true

require "pathname"
require "open3"

module LocalPostCss
  class Engine
    def initialize(source, options = {})
      @script = resolve_script(source, options[:script])
      @config = resolve_config(source, options[:config])
    end

    def process(page)
      file_path = Pathname.new(page.site.dest + page.url)
      stdout, stderr, status = Open3.capture3(@script, file_path.to_s, "-r", "--config", @config)

      if status.success?
        message = stdout.to_s.strip
        message = " #{message}" unless message.empty?
        Jekyll.logger.info "PostCSS:", "Rewrote #{page.url}#{message}"
      else
        Jekyll.logger.error "PostCSS:", "Failed to process #{page.url}"
        Jekyll.logger.error "PostCSS:", stderr unless stderr.to_s.strip.empty?
        Jekyll.logger.error "PostCSS:", stdout unless stdout.to_s.strip.empty?
        exit status.exitstatus || 1
      end
    end

    private

    def resolve_script(source, script)
      if script
        path = expand_script(source, script)
        return path if File.exist?(path)

        if Gem.win_platform? && !script.end_with?(".cmd")
          cmd_path = expand_script(source, "#{script}.cmd")
          return cmd_path if File.exist?(cmd_path)
        end

        Jekyll.logger.error "PostCSS:", "Couldn't find #{path}"
        exit 1
      end

      candidates = [
        "node_modules/.bin/postcss",
        "node_modules/.bin/postcss.cmd",
      ]

      candidates.each do |candidate|
        path = expand_script(source, candidate)
        return path if File.exist?(path)
      end

      Jekyll.logger.error "PostCSS:",
                          "PostCSS not found.
                           Make sure postcss and postcss-cli
                           are installed in your Jekyll source."
      Jekyll.logger.error "PostCSS:",
                          "Tried #{candidates.map { |c| expand_script(source, c) }.join(', ')}"
      exit 1
    end

    def resolve_config(source, config)
      config_path = File.expand_path(config || "postcss.config.js", source)
      return config_path if File.exist?(config_path)

      Jekyll.logger.error "PostCSS:", "postcss.config.js not found."
      Jekyll.logger.error "PostCSS:", "Couldn't find #{config_path}"
      exit 1
    end

    def expand_script(source, script)
      File.expand_path(script, source)
    end
  end
end

Jekyll::Hooks.register :pages, :post_write do |page|
  if %r!\.css$! =~ page.url
    engine = LocalPostCss::Engine.new(page.site.source, {
      script: page.site.config.dig("postcss", "script"),
      config: page.site.config.dig("postcss", "config"),
    })
    engine.process(page)
  end
end
