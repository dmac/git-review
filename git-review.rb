#!/usr/bin/env ruby
require "rubygems"
require "trollop"
require "net/smtp"
require "highline/import"

# TODO
# - set up "watches" (git review watch <author>)
# - be able to see how many reviews are in each watch queue (git review)
# - ability to mail to additional email addresses

parser = Trollop::Parser.new do
  banner <<-EOS
A code review utility for git.

Usage:
git review [options] <author>

Options:
EOS
  opt :num_commits, "Number of commits to review", :default => 1
  opt :paged, "Review commits in a paged view instead of in an editor", :default => false
  opt :keep, "Keep your review files instead of deleting them", :default => false
end

@opts = Trollop::with_standard_exception_handling parser do
  opts = parser.parse ARGV
  raise Trollop::HelpNeeded if ARGV.empty?
  opts
end

def initialize_env
  ENV["LESS"] = "-XRS"
  STDOUT.sync = true
  @workspace = "#{File::expand_path("~")}/.git-review"
  system("mkdir -p #{@workspace}")
end

def initialize_smtp(server = "smtp.gmail.com", port = 587)
  @smtp = Net::SMTP.new server, port
  @smtp.enable_starttls
end

def initialize_reviewer_and_author_info
  @author = ARGV[0]
  log = `git log -n 1 --author=#{@author}`
  @reviewer_name = `git config user.name`
  @reviewer_email = `git config user.email`.strip
  @author_name = log.match(/Author: (.+) </)[1]
  @author_email = log.match(/Author: .* <(.+)>/)[1]
  @password = nil
end

def cleanup
  system("rm -f #{@workspace}/diff_*.tmp*")
  system("rm -f #{@workspace}/review_*.txt*") unless @opts[:keep]
end

def get_commit_info(hash)
  wc = `git whatchanged -n 1 --oneline #{hash}`
  subject = wc.match(/ (.*)\n/)[1]
  files = wc.split("\n")[1..-1].map do |line|
    line.match(/\s(\S+)$/)[1]
  end
  return { :subject => subject, :files => files }
end

def send_email(subject, body)
  @password ||= ask("Password: ") { |q| q.echo = false }
  print "Sending mail..."
  message = "From: #{@reviewer_name} <#{@reviewer_email}>\n"
  message << "To: #{@author_name} <#{@author_email}>\n"
  message << "Subject: Re: #{hash} by #{@author_name} #{subject}\n\n"
  message << body
  @smtp.start("smtp.gmail.com", "#{@reviewer_email}", "#{@password}", :plain) do |smtp|
    smtp.send_message(message, "#{@reviewer_email}", "#{@author_email}")
  end
  puts "\nReview sent!"
end

def process_commit(hash)
  # TODO: open your own editor with convenient filenames?
  if @opts[:paged]
    system("clear; git show #{hash}")
  else
    commit_info = get_commit_info(hash)
    review_file = "#{@workspace}/review_#{hash}.txt"
    diff_file = "#{@workspace}/diff_#{hash}.tmp"
    unless File.exists?(review_file)
      system("echo '#{hash} #{commit_info[:subject]}\n' >> #{review_file}")
      commit_info[:files].each { |filename| system("echo '#{filename}\n' >> #{review_file}") }
    end

    system("git show #{hash} > #{diff_file}")
    system("vi -c ':wincmd l' -O #{diff_file} #{review_file}")

    print "Send review to #{@author_name} <#{@author_email}>? (Y/n): "
    input = STDIN.gets.chomp

    if ["", "y", "Y"].include? input
      body = ""
      File.open(review_file, "r") { |file| body = file.read }
      send_email(commit_info[:subject], body) unless body.empty?
    end
  end
end

if __FILE__ == $0
  initialize_env
  initialize_smtp
  initialize_reviewer_and_author_info

  log = `git log -n #{@opts[:num_commits]} --oneline --author=#{@author}`
  commits = log.split("\n").map { |line| line.split[0] }
  commits.each do |hash|
    process_commit(hash)
  end

  cleanup
end