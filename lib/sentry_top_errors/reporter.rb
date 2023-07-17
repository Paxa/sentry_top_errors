require 'progress_bar'

class SentryTopErrors::Reporter
  def initialize(client:, prod_regex: /^p-/, threshold_24h: 30, threshold_new: 10, new_days_num: 1, report_type: :html)
    @client = client
    @prod_regex = prod_regex
    @threshold_24h = threshold_24h
    @threshold_new = threshold_new
    @new_days_num = new_days_num
    @report_type = report_type
  end

  def fetch_data
    puts "### Fetching sentry data"
    bar = ProgressBar.new(100)
    bar.write

    @projects = @client.list_projects
    bar.increment!
    bar.max = @projects.size + 1

    @issues = {}

    queue = Thread::Queue.new
    @projects.each do |project|
      queue << project
    end
    threads = []

    2.times do
      threads << Thread.new do
        while !queue.empty? && project = queue.pop
          begin
            @issues[project['slug']] = @client.list_issues(project['organization']['slug'], project['slug'], stats_period: '24h')
            bar.increment!
          rescue => error
            bar.puts "ERROR when fetching issues for project #{project['slug']}"
            bar.puts "#{error.class} #{error.message}\n#{error.backtrace.join("\n")}"
          end
        end
      end
    end

    threads.each(&:join)

    puts "### Fetching done"
  end

  def generate_report
    groups = {}

    issue_counts = []
    new_issues = []

    @projects.each do |project|
      issues = @issues[project['slug']]
      next if issues == nil

      is_production = !!(project['name'] =~ @prod_regex)

      issues.each do |issue|
        count_in_24h = issue['stats'].values.first.map {|row| row.last }.sum
        issue_summary = {
          project_name: project['name'],
          project_url: project.dig('organization', 'links', 'organizationUrl') + "/projects/#{project['slug']}",
          issue: issue['title'],
          culprit: issue['culprit'],
          issue_link: issue['permalink'],
          issue_count: count_in_24h,
          is_production: is_production
        }

        if count_in_24h > @threshold_24h
          issue_counts << issue_summary
        end

        first_seen = Time.parse(issue['firstSeen'])
        age_in_days = (Time.now - first_seen) / 86400.0
        if age_in_days < @new_days_num.to_f && count_in_24h > @threshold_new
          new_issues << issue_summary
        end
      end
    end

    # sort desc, with higher number on top, separate production and staging
    issue_counts.sort_by! do |issue|
      [issue[:is_production] ? 1 : 0, issue[:issue_count]]
    end
    issue_counts.reverse!

    new_issues.sort_by! do |issue|
      [issue[:is_production] ? 1 : 0, issue[:issue_count]]
    end
    new_issues.reverse!

    render_result(issue_counts, new_issues)
  end

  def render_result(issue_counts, new_issues)
    if @report_type == :tabs || @report_type == :text
      result = "\nRepeating issues\n\n"
      issue_counts.each do |issue|
        result << [issue[:issue_count], issue[:project_name], issue[:issue], issue[:culprit], issue[:issue_link]].join("\t") + "\n"
      end

      result << "\nNew issues\n\n"
      new_issues.each do |issue|
        result << [issue[:issue_count], issue[:project_name], issue[:issue], issue[:culprit], issue[:issue_link]].join("\t") + "\n"
      end
      return result
    elsif @report_type == :table
      require 'terminal-table'
      require 'colorize'

      all_table = Terminal::Table.new(headings: ["count", "project", "issue", "cause", "link"]) do |t|
        issue_counts.each do |issue|
          t << [
            issue[:is_production] ? issue[:issue_count].to_s.colorize(:yellow) : issue[:issue_count],
            issue[:project_name], pad_and_justify(issue[:issue], 70),
            pad_and_justify(issue[:culprit], 40),
            issue[:issue_link]
          ]
        end
      end

      new_table = Terminal::Table.new(headings: ["count", "project", "issue", "cause", "link"]) do |t|
        new_issues.each do |issue|
          t << [
            issue[:is_production] ? issue[:issue_count].to_s.colorize(:yellow) : issue[:issue_count],
            issue[:project_name], pad_and_justify(issue[:issue], 70),
            pad_and_justify(issue[:culprit], 40),
            issue[:issue_link]
          ]
        end
      end

      return "Repeating issues:\n#{all_table}\n\nNew issues\n#{new_table}"

    elsif @report_type == :html
      tpl_dir = File.join(File.expand_path(File.dirname(__FILE__) + "/../.."), "templates")
      html_content = File.read(tpl_dir + "/index.html")
      html_content.sub!(%{['ALL_ISSUE_COUNTS_PLACEHOLDER']}, JSON.pretty_generate(issue_counts))
      html_content.sub!(%{['NEW_ISSUE_COUNTS_PLACEHOLDER']}, JSON.pretty_generate(new_issues))

      puts "Saved index.html"
      File.write("./index.html", html_content)

      :ok
    else
      raise "Unknown report_type #{@report_type}"
    end
  end

  def pad_and_justify(str, width, justify = :l)
    new_str = []
    str.split("\n").each do |s1|
      s1.split('').each_slice(width).map {|x| x.join}.each do |s2|
        new_str <<
          case justify
          when :l
            s2.ljust(width)
          when :r
            s2.rjust(width)
          when :c
            s2.center(width)
          end
      end
    end
    new_str * "\n"
  end
end
