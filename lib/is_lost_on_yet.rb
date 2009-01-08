require 'rubygems'
gem 'activesupport', '~> 2.2'
gem 'sequel',        '~> 2.7'
gem 'twitter',       '~> 0.4'

require 'sequel'
require 'twitter'

# Mmm, timezones
require 'active_support/basic_object'
require 'active_support/time_with_zone'
require 'active_support/values/time_zone'
require 'active_support/core_ext/object'
require 'active_support/core_ext/date'
require 'active_support/core_ext/numeric'
require 'active_support/core_ext/time'
require 'active_support/duration'
require 'active_support/core_ext/integer/time'
class Integer #:nodoc:
  include ActiveSupport::CoreExtensions::Integer::Time
end

module IsLOSTOnYet
  class << self
    attr_writer   :twitter_user
    attr_accessor :twitter_login
    attr_accessor :twitter_password
    attr_accessor :time_zone

    def twitter
      @twitter ||= Twitter::Base.new(twitter_login, twitter_password)
    end

    def twitter_user
      @twitter_user ||= User.find(:login => twitter_login) || begin
        twit = twitter.user(twitter_login)
        User.create(:login => twitter_login, :external_id => twit.id, :avatar_url => twit.profile_image_url)
        twitter_user
      end
    end

    def init
      yield if block_given?
      %w(episode answer user post).each { |l| require "is_lost_on_yet/#{l}" }
      Time.zone = time_zone
    end
  end

  self.time_zone = "UTC"
end

require 'is_lost_on_yet/schema'