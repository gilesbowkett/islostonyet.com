require File.join(File.dirname(__FILE__), 'test_helper')
class PostTest < Test::Unit::TestCase
  describe "#formatted_body" do
    it "clears initial @reply to twitter bot" do
      IsLOSTOnYet::Post.new(:body => "@#{IsLOSTOnYet.twitter_login} hi").formatted_body.should == "hi"
    end

    it "autolinks urls" do
      IsLOSTOnYet::Post.new(:body => "hi http://islostonyet.com").formatted_body.should == "hi <a href=\"http://islostonyet.com\">http://islostonyet.com</a>"
    end

    it "autolinks twitter users" do
      IsLOSTOnYet::Post.new(:body => "hi @technoweenie").formatted_body.should == "hi <a href=\"http://twitter.com/technoweenie\">@technoweenie</a>"
    end

    it "autolinks tags" do
      IsLOSTOnYet::Post.new(:body => "hi #timeloop").formatted_body.should == "hi <a href=\"/timeloop\">#timeloop</a>"
    end
  end

  describe "Selecting Posts" do
    before :all do
      cleanup IsLOSTOnYet::Post, IsLOSTOnYet::User
      transaction do
        @user1 = IsLOSTOnYet::User.new(:external_id => '1', :login => 'abc', :avatar_url => 'http://abc')
        @user2 = IsLOSTOnYet::User.new(:external_id => '2', :login => 'def', :avatar_url => 'http://def')
        [@user1, @user2].each { |u| u.save }
        @post1 = IsLOSTOnYet::Post.new(:user_id => @user1.id, :external_id => '1', :body => 'a', :created_at => Time.utc(2000, 1, 1), :visible => true)
        @post2 = IsLOSTOnYet::Post.new(:user_id => @user1.id, :external_id => '2', :body => 'b', :created_at => Time.utc(2000, 1, 2), :visible => true)
        @post3 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '3', :body => 'c', :created_at => Time.utc(2000, 1, 3), :visible => true)
        @post4 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '4', :body => 'd', :created_at => Time.utc(2000, 1, 4), :visible => true)
        @post5 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '5', :body => 'e', :created_at => Time.utc(2000, 1, 5), :visible => true)
        [@post1, @post2, @post3, @post4, @post5].each { |p| p.save }
      end
      IsLOSTOnYet.twitter_user = @user1
    end

    it "finds updates" do
      IsLOSTOnYet::Post.list.should == [@post5, @post4, @post3, @post2, @post1]
    end
  end

  describe "Post 'since_id' values" do
    before :all do
      cleanup IsLOSTOnYet::Post, IsLOSTOnYet::User
      transaction do
        @user1 = IsLOSTOnYet::User.new(:external_id => '1', :login => 'abc', :avatar_url => 'http://abc')
        @user2 = IsLOSTOnYet::User.new(:external_id => '2', :login => 'def', :avatar_url => 'http://def')
        [@user1, @user2].each { |u| u.save }
        @post1 = IsLOSTOnYet::Post.new(:user_id => @user1.id, :external_id => '1', :body => 'a', :created_at => Time.utc(2000, 1, 1), :visible => true)
        @post2 = IsLOSTOnYet::Post.new(:user_id => @user1.id, :external_id => '2', :body => 'b', :created_at => Time.utc(2000, 1, 2))
        @post3 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '3', :body => "@#{IsLOSTOnYet.twitter_login} blah", :created_at => Time.utc(2000, 1, 3), :visible => true)
        @post4 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '4', :body => "@#{IsLOSTOnYet.twitter_login} blah", :created_at => Time.utc(2000, 1, 4))
        @post5 = IsLOSTOnYet::Post.new(:user_id => 234234234, :external_id => '5', :body => 'd', :created_at => Time.utc(2000, 1, 1))
        [@post1, @post2, @post3, @post4, @post5].each { |p| p.save }
      end
      IsLOSTOnYet.twitter_user = @user1
    end

    before do
      @twitter = Object.new
      IsLOSTOnYet.load_episodes :sample
      stub(IsLOSTOnYet).twitter { @twitter }
    end

    it "finds latest external_id for searches" do
      IsLOSTOnYet::Post.latest_search.external_id.should == 5
    end

    it "finds latest external_id for updates" do
      IsLOSTOnYet::Post.latest_update.external_id.should == 2
    end

    it "finds latest external_id for replies" do
      IsLOSTOnYet::Post.latest_reply.external_id.should == 4
    end

    it "uses latest update external_id when processing updates" do
      mock(@twitter).timeline(*[:user, {:since_id => 2}]) { [] }
      IsLOSTOnYet::Post.process_updates
    end

    it "uses latest reply external_id when processing replies" do
      mock(@twitter).replies(*[{:since_id => 4}]) { [] }
      IsLOSTOnYet::Post.process_replies
    end

    it "uses latest search external_id when processing searches" do
      mock.instance_of(Twitter::Search).since(5)
      mock.instance_of(Twitter::Search).fetch { {'results' => []} }
      IsLOSTOnYet::Post.process_search
    end

    it "uses no update external_id when processing first updates" do
      stub(IsLOSTOnYet::Post).latest_update { nil }
      mock(@twitter).timeline(*[:user]) { [] }
      IsLOSTOnYet::Post.process_updates
    end

    it "uses no reply external_id when processing first replies" do
      stub(IsLOSTOnYet::Post).latest_reply { nil }
      mock(@twitter).replies(*[]) { [] }
      IsLOSTOnYet::Post.process_replies
    end

    it "uses no search external_id when processing first searches" do
      stub(IsLOSTOnYet::Post).latest_search { nil }
      stub.instance_of(Twitter::Search).since { raise ArgumentError }
      mock.instance_of(Twitter::Search).fetch { {'results' => []} }
      IsLOSTOnYet::Post.process_search
    end
  end

  describe "Post#process_updates" do
    before :all do
      cleanup IsLOSTOnYet::Post, IsLOSTOnYet::User
      @twitter    = Object.new
      @twit_user  = Faux::User.new(1, IsLOSTOnYet.twitter_login, 'http://avatar')
      @twit_posts = [
        Faux::Post.new(1, "&quot;Previously, on expos\303\251&quot;\n\n#lost", @twit_user, 'Sun Jan 04 23:04:16 UTC 2009'), 
        Faux::Post.new(2, '@bob hi', @twit_user, 'Sun Jan 04 23:04:17 UTC 2009')]
      @twit_post  = @twit_posts.first
      stub(IsLOSTOnYet).twitter { @twitter }
      IsLOSTOnYet.twitter_user = nil
    end

    describe "without existing user" do
      before :all do
        stub(@twitter).user { @twit_user }
        stub(@twitter).timeline(:user) { @twit_posts.dup }

        IsLOSTOnYet::Post.process_updates

        @user  = IsLOSTOnYet::User.find(:external_id => @twit_user.id)
        @post1 = IsLOSTOnYet::Post.find(:external_id => @twit_post.id)
        @post2 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[1].id)
      end

      it "creates user" do
        IsLOSTOnYet::User.count.should == 1
        @user.login.should      == @twit_user.screen_name
        @user.avatar_url.should == @twit_user.profile_image_url
      end

      it "creates posts" do
        IsLOSTOnYet::Post.count.should == 2
      end

      it "creates visible post" do
        @post1.body.should       == "&quot;Previously, on expos&#233;&quot;\n\n#lost"
        @post1.created_at.should == Time.utc(2009, 1, 4, 23, 4, 16)
        assert @post1.visible?
      end

      it "creates hidden post" do
        @post2.body.should       == @twit_posts[1].text
        @post2.created_at.should == Time.utc(2009, 1, 4, 23, 4, 17)
        assert !@post2.visible?
      end

      it "links post to user" do
        @post1.user_id.should == @user.id
        @post2.user_id.should == @user.id
      end
    end

    describe "with existing user" do
      before :all do
        stub(@twitter).timeline(:user) { [@twit_post] }

        @user = IsLOSTOnYet::User.new(:external_id => @twit_user.id, :login => 'abc', :avatar_url => 'http://')
        @user.save

        IsLOSTOnYet.twitter_user = @user
        IsLOSTOnYet::Post.process_updates

        @user.reload
        @post = IsLOSTOnYet::Post.find(:external_id => @twit_post.id)
      end

      it "uses existing user" do
        IsLOSTOnYet::User.count.should == 1
      end

      it "updates user attributes" do
        @user.login.should      == @twit_user.screen_name
        @user.avatar_url.should == @twit_user.profile_image_url
      end

      it "creates post" do
        @post.body.should       == "&quot;Previously, on expos&#233;&quot;\n\n#lost"
        @post.created_at.should == Time.utc(2009, 1, 4, 23, 4, 16)
      end

      it "links post to user" do
        @post.user_id.should == @user.id
      end
    end
  end

  describe "Post#valid_search_result" do
    it "accepts a post with two keywords" do
      assert IsLOSTOnYet::Post.new(:body => 'blah kate jack').valid_search_result?
    end

    it "accepts a post with hash keywords" do
      assert IsLOSTOnYet::Post.new(:body => 'blah #lost').valid_search_result?
    end

    it "accepts a post with one main keyword and one secondary" do
      assert IsLOSTOnYet::Post.new(:body => 'blah !kate tv').valid_search_result?
    end

    it "rejects a post with one main keyword and no secondary" do
      assert !IsLOSTOnYet::Post.new(:body => 'blah kate? jacked').valid_search_result?
    end

    it "rejects a post with no main keywords" do
      assert !IsLOSTOnYet::Post.new(:body => 'blah tv season lojack kater').valid_search_result?
    end

    before :all do
      @old_search = IsLOSTOnYet.twitter_search_options
      IsLOSTOnYet.twitter_search_options = {:main_keywords => %w(kate jack #lost), :secondary_keywords => %w(season tv)}
    end

    after :all do
      IsLOSTOnYet.twitter_search_options = @old_search
    end
  end

  describe "Post#process_search" do
    before :all do
      @twit_users = [Faux::User.new(1, IsLOSTOnYet::twitter_login, 'http://bob'), Faux::User.new(2, 'fred', 'http://fred')]
      @twit_posts = [
        Faux::Post.new(1, 'hi1',                                   @twit_users.first, 'Sun Jan 04 23:04:16 UTC 2009'), 
        Faux::Post.new(2, "@#{IsLOSTOnYet.twitter_login} ? #s1e2", @twit_users.last, 'Sun Jan 04 23:04:17 UTC 2009'),
        Faux::Post.new(3, "zomg",                                  @twit_users.last, 'Sun Jan 04 23:04:18 UTC 2009')]

      cleanup IsLOSTOnYet::Post, IsLOSTOnYet::User

      @user1 = IsLOSTOnYet::User.new(:external_id => @twit_users[0].id, :login => 'abc', :avatar_url => 'http://')
      @user1.save

      stub.instance_of(Twitter::Search).fetch do
        {'max_id' => 100000, 'since_id' => 0, 'results' => @twit_posts.map { |p| p.to_search_result }}
      end

      IsLOSTOnYet.twitter_user = @user1
      IsLOSTOnYet::Post.process_search

      @user1.reload
      @user2 = IsLOSTOnYet::User.find(:external_id => @twit_users[1].id)
      @post1 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[0].id)
      @post2 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[1].id)
      @post3 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[2].id)
    end

    it "uses existing user" do
      IsLOSTOnYet::User.count.should == 2
      @user1.login.should            == @twit_users[0].screen_name
      @user1.avatar_url.should       == @twit_users[0].profile_image_url
    end

    it "creates hidden post from twitter_login" do
      @post1.body.should       == @twit_posts[0].text
      @post1.created_at.should == Time.utc(2009, 1, 4, 23, 4, 16)
      assert !@post1.visible?
    end

    it "creates hidden post replying to twitter_login" do
      @post2.body.should       == @twit_posts[1].text
      @post2.created_at.should == Time.utc(2009, 1, 4, 23, 4, 17)
      assert !@post2.visible?
    end

    it "creates visible post without reply to twitter_login" do
      @post3.body.should       == @twit_posts[2].text
      @post3.created_at.should == Time.utc(2009, 1, 4, 23, 4, 18)
      assert @post3.visible?
    end

    it "creates user" do
      @user2.login.should      == @twit_users[1].screen_name
      @user2.avatar_url.should == @twit_users[1].profile_image_url
    end

    it "creates posts" do
      IsLOSTOnYet::Post.count.should == 3
    end

    it "links post to user" do
      @post1.user_id.should == @user1.id
      @post2.user_id.should == @user2.id
      @post3.user_id.should == @user2.id
    end
  end

  describe "Post#process_replies" do
    before :all do
      @twitter    = Object.new
      @twit_users = [Faux::User.new(1, 'bob', 'http://bob'), Faux::User.new(2, 'fred', 'http://fred')]
      @twit_posts = [
        Faux::Post.new(1, 'hi1',                                   @twit_users.first, 'Sun Jan 04 23:04:16 UTC 2009'), 
        Faux::Post.new(2, "@#{IsLOSTOnYet.twitter_login} ? #s1e2", @twit_users.last, 'Sun Jan 04 23:04:17 UTC 2009'),
        Faux::Post.new(3, "@#{IsLOSTOnYet.twitter_login}?",        @twit_users.last, 'Sun Jan 04 23:04:18 UTC 2009'),
        Faux::Post.new(4, "@#{IsLOSTOnYet.twitter_login} ? ",      @twit_users.last, 'Sun Jan 04 23:04:19 UTC 2009')]
      stub(IsLOSTOnYet).twitter { @twitter }

      cleanup IsLOSTOnYet::Post, IsLOSTOnYet::User

      @user1 = IsLOSTOnYet::User.new(:external_id => @twit_users[0].id, :login => 'abc', :avatar_url => 'http://')
      @user1.save

      stub(@twitter).replies { @twit_posts.dup }
      stub(@twitter).update("@fred abc")
      stub(IsLOSTOnYet).answer { IsLOSTOnYet::Answer.new(Time.now.utc, IsLOSTOnYet::Episode.new('s1e1', nil, 3.days.ago), nil, :yes, 'abc') }

      IsLOSTOnYet.twitter_user = @user1
      IsLOSTOnYet::Post.process_replies

      @user1.reload
      @user2 = IsLOSTOnYet::User.find(:external_id => @twit_users[1].id)
      @post1 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[0].id)
      @post2 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[1].id)
      @post3 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[2].id)
      @post4 = IsLOSTOnYet::Post.find(:external_id => @twit_posts[3].id)
    end

    it "uses existing user" do
      IsLOSTOnYet::User.count.should == 2
      @user1.login.should            == @twit_users[0].screen_name
      @user1.avatar_url.should       == @twit_users[0].profile_image_url
    end

    it "creates user" do
      @user2.login.should      == @twit_users[1].screen_name
      @user2.avatar_url.should == @twit_users[1].profile_image_url
    end

    it "creates posts" do
      IsLOSTOnYet::Post.count.should == 4
    end

    it "creates visible posts" do
      @post1.body.should       == @twit_posts[0].text
      @post1.created_at.should == Time.utc(2009, 1, 4, 23, 4, 16)
      assert @post1.visible?
      @post2.body.should       == @twit_posts[1].text
      @post2.created_at.should == Time.utc(2009, 1, 4, 23, 4, 17)
      assert @post2.visible?
    end

    it "creates hidden posts from inquiries" do
      @post3.body.should       == @twit_posts[2].text
      @post3.created_at.should == Time.utc(2009, 1, 4, 23, 4, 18)
      assert !@post3.visible?
      @post4.body.should       == @twit_posts[3].text
      @post4.created_at.should == Time.utc(2009, 1, 4, 23, 4, 19)
      assert !@post4.visible?
    end

    it "links post to user" do
      @post1.user_id.should == @user1.id
      @post2.user_id.should == @user2.id
      @post3.user_id.should == @user2.id
      @post4.user_id.should == @user2.id
    end
  end

  describe "Post#cleanup_posts" do
    before :all do
      @user1 = IsLOSTOnYet::User.new(:external_id => '1', :login => 'abc', :avatar_url => 'http://abc')
      @user2 = IsLOSTOnYet::User.new(:external_id => '2', :login => 'def', :avatar_url => 'http://def')
      [@user1, @user2].each { |u| u.save }
      IsLOSTOnYet.twitter_user = @user1

      # updates
      @post1 = IsLOSTOnYet::Post.new(:user_id => @user1.id, :external_id => '1', :body => 'a', :created_at => Time.utc(2000, 1, 1), :visible => false)
      @post2 = IsLOSTOnYet::Post.new(:user_id => @user1.id, :external_id => '2', :body => 'a', :created_at => Time.utc(2000, 1, 2), :visible => true)
      @post3 = IsLOSTOnYet::Post.new(:user_id => @user1.id, :external_id => '3', :body => 'a', :created_at => Time.utc(2000, 1, 3), :visible => false)

      # replies
      @post4 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '4', :body => "@#{IsLOSTOnYet.twitter_login} blah", :created_at => Time.utc(2000, 1, 4), :visible => false)
      @post5 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '5', :body => "@#{IsLOSTOnYet.twitter_login} blah", :created_at => Time.utc(2000, 1, 5), :visible => true)
      @post6 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '6', :body => "@#{IsLOSTOnYet.twitter_login} blah", :created_at => Time.utc(2000, 1, 6), :visible => false)

      # searches
      @post7 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '7', :body => "b", :created_at => Time.utc(2000, 1, 7), :visible => false)
      @post8 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '8', :body => "b", :created_at => Time.utc(2000, 1, 8), :visible => true)
      @post9 = IsLOSTOnYet::Post.new(:user_id => @user2.id, :external_id => '9', :body => "b", :created_at => Time.utc(2000, 1, 9), :visible => false)
      [@post1, @post2, @post3, @post4, @post5, @post6, @post7, @post8, @post9].each { |p| p.save }

      IsLOSTOnYet::Post.count.should == 9
      IsLOSTOnYet::Post.cleanup
    end

    it "removes old invisible posts" do
      IsLOSTOnYet::Post.count.should == 6
    end

    it "removes old invisible update" do
      IsLOSTOnYet::Post.where(:id => @post1.id).first.should == nil
    end

    it "removes old invisible reply" do
      IsLOSTOnYet::Post.where(:id => @post4.id).first.should == nil
    end

    it "removes old invisible search" do
      IsLOSTOnYet::Post.where(:id => @post7.id).first.should == nil
    end
  end
end