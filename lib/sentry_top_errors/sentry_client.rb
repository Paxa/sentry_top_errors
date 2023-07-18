class SentryTopErrors::SentryClient
  SENTRY_HOST = 'https://sentry.io'
  HTTP_OPTIONNS = {
    tcp_nodelay: true,
    connect_timeout: 10,
    read_timeout: 40,
    idempotent: true,
    retry_limit: 3
  }

  def initialize(sentry_key: , enable_cache: false)
    @sentry_key = sentry_key
    @enable_cache = enable_cache
  end

  def http(method, path, options = {}, retry_count = 0)
    @conn ||= Excon.new(SENTRY_HOST, HTTP_OPTIONNS)
    options[:headers] ||= {}
    options[:headers]['Authorization'] ||= "Bearer #{@sentry_key}"
    response = @conn.request({method: method, path: path}.merge(options))

    # status 429 = too many requests
    if response.status == 429 && retry_count < 4
      sleep(0.2)
      return http(method, path, options, retry_count + 1)
    end

    SentryTopErrors::ApiResponse.new_from_res(response)
  end

  def get_all_with_cursor(http_method, url_path, http_options = {})
    objects = http(http_method, url_path, http_options)
    link_header = objects.headers['link']

    while link_header && link_header =~ /rel="next"/
      cursor_match = link_header.match(/results="true";\s+cursor="([\d:]+?)"$/)
      if cursor_match
        http_options[:query] ||= {}
        http_options[:query][:cursor] = cursor_match[1]
        next_objects = http(http_method, url_path, http_options)
        objects.concat(next_objects)
        link_header = next_objects.headers['link']
      else
        link_header = ""
        # puts "No next link in response"
      end
    end

    objects
  end

  def list_projects
    cached(:all_projects) do
      get_all_with_cursor(:get, 'api/0/projects/')
    end
  end

  def list_issues(org_slug, project_slug, stats_period: '24h')
    cached("list_issues_#{project_slug}") do
      query = {statsPeriod: stats_period}
      get_all_with_cursor(:get, "api/0/projects/#{org_slug}/#{project_slug}/issues/", query: query)
    end
  end

  def cached(key, &block)
    if @enable_cache
      cache_file = "sentry_cache/#{key}.yaml"
      if File.exist?(cache_file)
        YAML.load_file(cache_file, aliases: true, permitted_classes: [
          SentryTopErrors::ApiResponse::FromArray, SentryTopErrors::ApiResponse::FromHash, Symbol, Excon::Response, Excon::Headers
        ])
      else
        result = block.call()
        File.write(cache_file, YAML.dump(result))
        result
      end
    else
      block.call()
    end
  end

  def drop_cache
    Dir.glob("sentry_cache/*.yaml").each do |file|
      File.unlink(file)
    end
  end
end
