class ProcessInteractionService
  include ApplicationHelper

  def call(envelope, target_account)
    body = salmon.unpack(envelope)
    xml  = Nokogiri::XML(body)

    return unless contains_author?(xml)

    username = xml.at_xpath('/xmlns:entry/xmlns:author/xmlns:name').content
    url      = xml.at_xpath('/xmlns:entry/xmlns:author/xmlns:uri').content
    domain   = Addressable::URI.parse(url).host
    account  = Account.find_by(username: username, domain: domain)

    if account.nil?
      account = follow_remote_account_service.("acct:#{username}@#{domain}")
      return if account.nil?
    end

    if salmon.verify(envelope, account.keypair)
      case verb(xml)
      when :follow
        follow!(account, target_account)
      when :unfollow
        unfollow!(account, target_account)
      when :favorite
        favourite!(xml, account)
      when :post
        add_post!(body, account) if mentions_account?(xml, target_account)
      when :share
        add_post!(body, account) unless status(xml).nil?
      end
    end
  end

  private

  def contains_author?(xml)
    !(xml.at_xpath('/xmlns:entry/xmlns:author/xmlns:name').nil? || xml.at_xpath('/xmlns:entry/xmlns:author/xmlns:uri').nil?)
  end

  def mentions_account?(xml, account)
    xml.xpath('/xmlns:entry/xmlns:link[@rel="mentioned"]').each { |mention_link| return true if mention_link.attribute('ref') == profile_url(name: account.username) }
    false
  end

  def verb(xml)
    xml.at_xpath('//activity:verb').content.gsub('http://activitystrea.ms/schema/1.0/', '').to_sym
  rescue
    :post
  end

  def follow!(account, target_account)
    account.follow!(target_account)
  end

  def unfollow!(account, target_account)
    account.unfollow!(target_account)
  end

  def favourite!(xml, from_account)
    status(xml).favourites.first_or_create!(account: from_account)
  end

  def add_post!(body, account)
    process_feed_service.(body, account)
  end

  def status(xml)
    Status.find(unique_tag_to_local_id(activity_id, 'Status'))
  end

  def activity_id(xml)
    xml.at_xpath('/xmlns:entry/xmlns:id').content
  end

  def salmon
    OStatus2::Salmon.new
  end

  def follow_remote_account_service
    FollowRemoteAccountService.new
  end

  def process_feed_service
    ProcessFeedService.new
  end
end