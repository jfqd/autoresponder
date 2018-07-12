# encoding: utf-8
require 'fileutils'
require 'rubygems'
require 'mail'
require 'pony'
require 'date'
require 'time'
require 'mysql2'
require 'sequel'
require 'dotenv'
Dotenv.load

begin
  DB = Sequel.connect(
    :adapter => 'mysql2',
    :user => ENV['MYSQL_USER'],
    :host => ENV['MYSQL_HOST'],
    :database => ENV['MYSQL_DATABASE'],
    :password=> ENV['MYSQL_PWD']
  )
rescue Exception => e
  STDERR.puts "ERROR: failed to connect to Database!"
  exit 1
end

begin
  require 'redis'
  REDIS = Redis.new(
    host: ENV['REDIS_HOST'],
    port: ENV['REDIS_PORT'],
    db:   ENV['REDIS_DB']
  )
rescue Exception => e
  STDERR.puts "ERROR: failed to connect to Redis!"
end

def now
  Time.now.utc
end

def autoreply?(mail)
  ignored_headers = {
    'X-Auto-Response-Suppress' => /(all|oof)/i,
    'X-Autoreply'              => /\A.{1,}\z/,
    'X-Autorespose'            => /\A.{1,}\z/,
    'X-Autorespond'            => /\A.{1,}\z/,
    'Auto-Submitted'           => /\Aauto-/i
  }
  ignored_headers.each do |key, ignored_value|
    value = nil
    mail.header_fields.each {|f| value = f.value if f.name == key }
    if value
      value = value.to_s.downcase
      if (ignored_value.is_a?(Regexp) && value.match(ignored_value)) || value == ignored_value
        puts "ignoring autoreply email with #{key}:#{value} header"
        return true
      end
    end
  end
  return false
end

def mailinglist?(mail)
  skip = false
  a = ['List-Id', 'List-Unsubscribe', 'Feedback-ID']
  mail.header_fields.each {|f| skip=true if a.include?(f.name) }
  return skip
end

def unwanted_from?(from)
  from =~ /MAILER.DAEMON/i ||
  from =~ /^root@/i ||
  from =~ /\.local/i ||
  from == 'invalid@emailaddress.com' ||
  from.include?('abuse') ||
  from.include?('postmaster') ||
  from.include?('hostmaster') ||
  from.include?('amazon') ||
  from.include?('no-replay') ||
  from.include?('no-reply') ||
  from.include?('noreply') ||
  from.include?('preisvergleich') ||
  from.include?('news@') ||
  from.include?('@news') ||
  from.include?('support@') ||
  from.include?('newsletter')
end

def spam?(mail)
  value = nil
  mail.header_fields.each {|f| value = f.value if f.name.downcase == 'x-spam-score' }
  value.to_f > 4.00 ? true : false
end

def send_mail(to,from,message)
  Pony.mail(
    :to      => to,
    :from    => from,
    :subject => ENV['SUBJECT'],
    :body    => message,
    :via => :smtp,
    :headers => { "X-Auto-Response-Suppress" => "All" },
    :via_options => {
      :address              => ENV['MAILSERVER'],
      :port                 => ENV['PORT'],
      :enable_starttls_auto => true,
      :user_name            => ENV['MAILUSER'],
      :password             => ENV['MAILPDW'],
      :authentication       => :plain,
      :domain               => ENV['DOMAIN']
    }
  )
  # from = to whom it was send!
  # to   = from whom it was received!
  prevent_resend_to_same_sender(from,to)
end

# to   = to whom it was send
# from = from whom it was received
def prevent_resend_to_same_sender(to,from)
  return if REDIS == nil
  one_week = 86400 * 7
  REDIS.hmset( 
    "#{to}_#{from}",
    'delivered', now.to_i
  )
  REDIS.expire("#{to}_#{from}", one_week)
end

# to   = to whom it was send
# from = from whom it was received
def previously_send?(to,from)
  return false if REDIS == nil
  r = REDIS.hmget( 
    "#{to}_#{from}",
    'delivered'
  )
  r.class == Array && r.first != nil
end

puts "## Starting: #{now} ##"

# find mailboxes to process
mailboxes  = DB[:users].where(autoresponder: 1).all
mailboxes.each do |mailbox|
  
  active     = mailbox[:active]
  address    = mailbox[:address]
  last_date  = mailbox[:changed_at] || now
  start_date = mailbox[:start_date]
  end_date   = mailbox[:end_date]
  message    = mailbox[:message]
  
  user       = address.split('@')[0]
  domain     = address.split('@')[1]
  
  mailbox_path  = "#{ENV['MAILBOX_PATH']}/#{domain}/#{user}/new"
  
  if active == true && now.to_date >= start_date && now.to_date <= end_date
    puts "Processing inbox for: #{address}"
    
    #for each new mail file
    Dir.new(mailbox_path).each do |filename|
      unless filename[0,1] == "."
        # act only if mail-file is newer
        mail_path = "#{mailbox_path}/#{filename}"
        mail_file = File.new(mail_path)
        # was it already processed?
        if mail_file.stat.mtime.utc > last_date
          mail = Mail.read(mail_path)
          from = mail.from.first rescue nil
          # test if we should process
          if mail && from && !unwanted_from?(from) && !mailinglist?(mail) && !autoreply?(mail) && !spam?(mail) && !previously_send?(address,from)
            # log to whom we are sending mail
            puts "*** Sending to: #{from}"
            send_mail(from,address,message)
          end # if !unwanted_from?(from) ...
          
        end # if mail.stat.mtime > last_date
      end # unless filename[0,1] == "."
    end # Dir.new(mailbox_path).each do |filename|
  end # if now >= start_date && now <= end_date
  
  # update the auto response file's mod time
  DB[:users].where(address: address).update(changed_at: now)
end # mailboxes.each

puts "## Ending:   #{now} ##"