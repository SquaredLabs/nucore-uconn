require "rails_helper"

RSpec.describe ResultsFileNotifier do
  let(:service) { FactoryGirl.create(:setup_service) }
  let(:order) { create(:purchased_order, product: service) }
  let(:stored_file) { FactoryGirl.create(:stored_file, :results, order_detail: order.order_details.first) }
  let(:notifier) { described_class.new(stored_file) }

  describe "with notifications enabled", feature_setting: { results_file_notifications: true } do
    it "sends a notification" do
      expect { notifier.notify }.to change(ActionMailer::Base.deliveries, :count).by(1)
    end

    describe "notifying a second time" do
      before { notifier.notify }

      describe "shortly after the first one" do
        it "does not send" do
          expect { notifier.notify }.not_to change(ActionMailer::Base.deliveries, :count)
        end
      end

      describe "a day later" do
        before { Timecop.travel(25.hours.from_now) }

        it "does send" do
          expect { notifier.notify }.to change(ActionMailer::Base.deliveries, :count).by(1)
        end
      end
    end
  end

  describe "with notifications disabled", feature_setting: { results_file_notifications: false } do
    it "does not send a notification" do
      expect { notifier.notify }.not_to change(ActionMailer::Base.deliveries, :count)
    end
  end

end
