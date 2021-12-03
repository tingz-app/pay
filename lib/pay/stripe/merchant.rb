module Pay
  module Stripe
    class Merchant
      attr_reader :pay_merchant

      delegate :processor_id,
        to: :pay_merchant

      def initialize(pay_merchant)
        @pay_merchant = pay_merchant
      end

      def create_account(**options)
        defaults = {
          type: "express",
          capabilities: {
            card_payments: {requested: true},
            transfers: {requested: true}
          }
        }

        stripe_account = ::Stripe::Account.create(defaults.merge(options))
        pay_merchant.update(processor_id: stripe_account.id)
        update_account_info!(account_info: stripe_account.to_hash.merge(updated_at: Time.current.to_i))
        stripe_account
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def account
        account_info = ::Stripe::Account.retrieve(processor_id).to_hash
        update_account_info!(account_info: account_info.merge(updated_at: Time.current.to_i))
        account_info
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def account_link(refresh_url:, return_url:, type: "account_onboarding", **options)
        ::Stripe::AccountLink.create({
          account: processor_id,
          refresh_url: refresh_url,
          return_url: return_url,
          type: type
        })
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # A single-use login link for Express accounts to access their Stripe dashboard
      def login_link(**options)
        ::Stripe::Account.create_login_link(processor_id)
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # Transfer money from the platform to this connected account
      # https://stripe.com/docs/connect/charges-transfers#transfer-availability
      def transfer(amount:, currency: "usd", **options)
        ::Stripe::Transfer.create({
          amount: amount,
          currency: currency,
          destination: processor_id
        }.merge(options))
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # Retrieve account balance
      # https://stripe.com/docs/connect/account-balances
      def balance
        return unless processor_id.present?

        balance_data = ::Stripe::Balance.retrieve({stripe_account: processor_id}).to_hash
        actual_balance = {balance: balance_data.merge(updated_at: Time.current.to_i)}

        update_account_info!(actual_balance)
        balance_data
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      private

      def update_account_info!(data = {})
        account_info = pay_merchant.account_info&.data || {}
        pay_merchant.update(account_info_attributes: {
          data: account_info.merge(data)
        })
      end
    end
  end
end
