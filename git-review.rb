#!/usr/bin/env ruby
require "rubygems"
require "trollop"
require "net/smtp"
require "highline/import"

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

opts = Trollop::with_standard_exception_handling parser do
  opts = parser.parse ARGV
  raise Trollop::HelpNeeded if ARGV.empty?
  opts
end

author = ARGV[0]
ENV["LESS"] = "-XRS"
STDOUT.sync = true

log = `git log -n 1 --author=#{author}`
reviewer_name = `git config user.name`
reviewer_email = `git config user.email`.strip
author_name = log.match(/Author: (.+) </)[1]
author_email = log.match(/Author: .* <(.+)>/)[1]

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
  end
end

print "Send reviews to #{author_name} <#{author_email}>? (Y/n): "
input = STDIN.gets.chomp

if ["", "y", "Y"].include? input
  password = ask("Password: ") { |q| q.echo = false }
  print "Sending mail"

  smtp = Net::SMTP.new "smtp.gmail.com", 587
  smtp.enable_starttls

  commits.each do |commit, subject|
    print "."

    message = "From: #{reviewer_name} <#{reviewer_email}>\n"
    message << "To: #{author_name} <#{author_email}>\n"
    message << "Subject: Re: #{subject} by #{author_name}\n\n"
    File.open("review_#{commit}.txt", "r") { |file| message << file.read }
    smtp.start("smtp.gmail.com", "#{reviewer_email}", "#{password}", :plain) do |smtp|
      smtp.send_message(message, "#{reviewer_email}", "#{author_email}")
    end
  end
  puts "\nReviews sent!"
end

system("rm -f diff_*.tmp")
system("rm -f review_*.txt") unless opts[:keep]
