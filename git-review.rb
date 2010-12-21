#!/usr/bin/env ruby
require "rubygems"
require "trollop"
require "net/smtp"
require "highline/import"

# TODO
# - refactor
# - set up "watches" (git review watch <author>)
# - be able to see how many reviews are in each watch queue (git review)
# - ability to mail to additional email addresses
# - don't save tmp files in top level git directory (/tmp? ~/.git-review?)

parser = Trollop::Parser.new do
  banner <<-EOS
A code review utility for git.

Usage:
git review [options] <author>

Options:
EOS
  opt :num_commits, "Number of commits to review", :default => 1
  opt :watch, "Set up a watch queue for an author", :default => false
  opt :status, "View your watch queues", :default => false
  opt :paged, "Review commits in a paged view instead of in an editor", :default => false
  opt :keep, "Keep your review files instead of deleting them", :default => false
end

opts = Trollop::with_standard_exception_handling parser do
  opts = parser.parse ARGV
  raise Trollop::HelpNeeded if ARGV.empty?
  opts
end

author = ARGV[0]
ENV["LESS"] = "-XRS"
STDOUT.sync = true

if opts[:watch]
  puts "You are now watching #{author}"
  puts "git review --status to view your watch queues"
  exit 0
end

if opts[:status]
  puts "philc has 5 new commits"
  exit 0
end

smtp = Net::SMTP.new "smtp.gmail.com", 587
smtp.enable_starttls

log = `git log -n 1 --author=#{author}`
reviewer_name = `git config user.name`
reviewer_email = `git config user.email`.strip
author_name = log.match(/Author: (.+) </)[1]
author_email = log.match(/Author: .* <(.+)>/)[1]
password = nil

log = `git log -n #{opts[:num_commits]} --oneline --author=#{author}`
commits = Hash[*log.split("\n").collect { |line| [line.split[0], nil] }.flatten]

commits.keys.each do |commit|
  # TODO: open your own editor with convenient filenames?
  if opts[:paged]
    system("clear; git show #{commit}")

  else
    wc = `git whatchanged -n 1 --oneline #{commit}`
    commits[commit] = wc.match(/ (.*)\n/)[1]
    files = wc.split("\n")[1..-1].map do |line|
      line[line.rindex("/") + 1..-1]
    end
    system("echo '#{commit} #{commits[commit]}\n' >> review_#{commit}.txt")
    files.each { |file| system("echo '#{file}\n' >> review_#{commit}.txt") }

    system("git show #{commit} > diff_#{commit}.tmp")
    system("vi -c ':wincmd l' -O diff_#{commit}.tmp review_#{commit}.txt")


    print "Send review to #{author_name} <#{author_email}>? (Y/n): "
    input = STDIN.gets.chomp

    if ["", "y", "Y"].include? input
      password ||= ask("Password: ") { |q| q.echo = false }
      print "Sending mail..."

      review = ""
      File.open("review_#{commit}.txt", "r") { |file| review = file.read }
      next if review.empty?

      message = "From: #{reviewer_name} <#{reviewer_email}>\n"
      message << "To: #{author_name} <#{author_email}>\n"
      message << "Subject: Re: #{commit} by #{author_name} #{commits[commit]}\n\n"
      message << review
      smtp.start("smtp.gmail.com", "#{reviewer_email}", "#{password}", :plain) do |smtp|
        smtp.send_message(message, "#{reviewer_email}", "#{author_email}")
      end
      puts "\nReview sent!"
    end
  end
end

system("rm -f diff_*.tmp")
system("rm -f review_*.txt") unless opts[:keep]
