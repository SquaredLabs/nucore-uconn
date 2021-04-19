# frozen_string_literal: true

module NucoreKfs

  module UsersControllerExtension

    def service_username_lookup(username)
      lookup = NucoreKfs::UconnUserLookup.new
      ldap_user = lookup.findByNetId(username)
      if ldap_user.nil?
        return nil
      end
      lookup.makeNucoreUserFromLdapUser(ldap_user)
    end

  end

end
