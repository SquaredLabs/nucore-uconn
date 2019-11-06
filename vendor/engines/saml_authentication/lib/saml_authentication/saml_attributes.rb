# frozen_string_literal: true

module SamlAuthentication

  class SamlAttributes

    delegate :[], :except, to: :to_h

    def initialize(saml_response)
      @saml_response = saml_response
    end

    def to_h
      @saml_response.attributes.resource_keys.each_with_object({}) do |key, memo|
        memo[key] = @saml_response.attribute_value_by_resource_key(key)
      end.with_indifferent_access
    end

  end

end
