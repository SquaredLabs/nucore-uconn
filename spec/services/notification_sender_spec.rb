# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationSender, :aggregate_failures do
  subject(:notification_sender) { described_class.new(facility, notification_params) }

  let(:notification_params) { { order_detail_ids: order_detail_ids } }
  let(:facility) { item.facility }
  let(:item) { FactoryBot.create(:setup_item, :with_facility_account) }
  let(:order_detail_ids) { order_details.map(&:id) }
  let(:delivery) { OpenStruct.new(deliver_now: true) }

  before(:each) do
    # This feature only gets used when there is a review period, so go ahead and enable it.
    allow(SettingsHelper).to receive(:has_review_period?).and_return true

    order_details.each(&:complete!)
  end

  describe "#perform" do
    context "notifications for $0 order_details" do
      let(:account_owner) { FactoryBot.create(:user) }
      let(:account) { FactoryBot.create(:setup_account, owner: account_owner) }

      context "when send $0 checkbox is checked" do
        let(:notification_params) { { order_detail_ids: order_detail_ids, notify_zero_dollar_orders: "1" } }
        let(:order_details) { [place_product_order(account_owner, facility, item, account)] }

        before { order_details.first.update!(actual_cost: 0) }

        it "sends a notification for $0 order_details" do
          expect(Notifier)
            .to receive(:review_orders)
            .with(user: account_owner,
                  accounts: [account],
                  facility: facility)
            .once
            .and_return(delivery)

          notification_sender.perform
        end
      end

      context "when send $0 checkbox is not checked" do
        let(:order_details) do
          [
            place_product_order(account_owner, facility, item, account),
            place_product_order(account_owner, facility, item, account),
          ]
        end

        it "sends no notification if all order_details are $0" do
          order_details.each { |od| od.update!(actual_cost: 0, actual_subsidy: 0) }

          expect(Notifier).not_to receive(:review_orders)

          notification_sender.perform
        end

        it "sends a notification if at least one order_detail has cost" do
          order_details.first.update!(actual_cost: 0, actual_subsidy: 0)

          expect(Notifier)
            .to receive(:review_orders)
            .with(user: account_owner,
                  accounts: [account],
                  facility: facility)
            .once
            .and_return(delivery)

          notification_sender.perform
        end

        it "sends a notification if the order_detail is $0 but has a subsidy" do
          order_details.each { |od| od.update!(actual_cost: 10, actual_subsidy: 10) }

          expect(Notifier)
            .to receive(:review_orders)
            .with(user: account_owner,
                  accounts: [account],
                  facility: facility)
            .once
            .and_return(delivery)

          notification_sender.perform
        end
      end
    end

    context "when multiple users administer multiple accounts" do
      let(:account_owners) { FactoryBot.create_list(:user, 2) }
      let(:accounts) do
        account_owners.map do |user|
          FactoryBot.create_list(:setup_account, 2, owner: user)
        end.flatten
      end
      let!(:order_details) do
        accounts.map do |account|
          FactoryBot.create(:account_user, :purchaser, user_id: purchaser.id, account_id: account.id)
          Array.new(3) { place_product_order(purchaser, facility, item, account) }
        end.flatten
      end
      let(:purchaser) { FactoryBot.create(:user) }

      context "and multiple accounts have complete orders" do
        it "notifies each user once while setting order_details to reviewed" do
          account_owners.each do |user|
            expect(Notifier)
              .to receive(:review_orders)
              .with(user: user,
                    accounts: match_array(AccountUser.where(user_id: user.id).map(&:account)),
                    facility: facility)
              .once
              .and_return(delivery)
          end

          expect(notification_sender.perform).to be_truthy
          expect(notification_sender.account_ids_to_notify).to match_array(accounts.map(&:id))
          expect(order_details.map(&:reload)).to be_all(&:reviewed_at?)
        end

      end

      context "when an order_detail ID is invalid" do
        let(:order_detail_ids) { [-1, order_details.first.id] }

        it "errors while not setting the valid ID as reviewed" do
          expect(notification_sender.perform).to be_falsey
          expect(notification_sender.errors.first).to include("-1")
          expect(order_details.first.reload).not_to be_reviewed
        end
      end
    end
  end
end
