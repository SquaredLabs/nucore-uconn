module NucoreKfs

  class UconnLdapUser
    attr_accessor :uid, :cn, :sn, :mail, :givenname
    def initialize(ldap_entry)
      @uid = ldap_entry.uid.first
      @cn = ldap_entry.cn.first
      @sn = ldap_entry.sn.first
      @mail = ldap_entry.mail.first
      @givenname = ldap_entry.givenname.first
    end
  end

  class UconnUserLookup

    def initialize
      # Load config
      config_file_path = Rails.root.join("config", "ldap.yml")

      unless File.exist?(config_file_path)
        @ldap = nil
        @bindSuccess = false
        return
      end

      parsed = ERB.new(File.read(config_file_path)).result
      yaml = YAML.safe_load(parsed, [], [], true) || {}
      config = yaml.fetch(Rails.env, {})

      host = config.fetch("host", "")
      port = config.fetch("port", "")
      admin_user = config.fetch("admin_user", "")
      admin_password = config.fetch("admin_password", "")
      @treebase = config.fetch("base", "")

      if host.empty?
        @ldap = nil
        @bindSuccess = false
        return
      end

      # init LDAP connection
      ldap = Net::LDAP.new(:encryption => {:method => :start_tls})
      ldap.host = host
      ldap.port = port
      ldap.auth admin_user, admin_password

      # Bind and store result for later use
      @bindSuccess = ldap.bind
      @ldap = ldap
    end

    def status
      @ldap.get_operation_result
    end

    def findByNetId(netid)
      if @ldap.nil?
        return nil
      end

      filter = Net::LDAP::Filter.eq('uid', netid)
      results = @ldap.search( :base => @treebase, :filter => filter )
      entry = results.first
      if entry.nil?
        nil
      else 
        UconnLdapUser.new(entry)
      end
    end

    def makeNucoreUserFromLdapUser(ldap_user)
      User.new(
        :username => ldap_user.uid,
        :first_name => ldap_user.givenname,
        :last_name => ldap_user.sn,
        :email => ldap_user.mail,
      )
    end

  end

end
