require "rails_helper"

RSpec.describe NucoreKfs::UconnUserLookup, type: :service do

  let(:valid_netid) { "jpo08003" }
  let(:invalid_netid) { "jpo08003213213121313" }
  let(:lookup) { described_class.new }

  it "sucessfully binds to LDAP" do
    expect(lookup.status).to be_truthy
  end

  it "can find a user by NetID" do
    user = lookup.findByNetId(valid_netid)
    expect(user).not_to be_nil
  end

  it "returns nil for invalid netid" do
    user = lookup.findByNetId(invalid_netid)
    expect(user).to be_nil
  end

  it "gets the correct attributes for a user" do
    user = lookup.findByNetId(valid_netid)
    expect(user.uid).to eq(valid_netid)
    expect(user.cn).to eq("Joseph P O'Shea")
    expect(user.givenname).to eq("Joseph")
  end

end
