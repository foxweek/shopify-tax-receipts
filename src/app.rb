require 'sinatra/shopify-sinatra-app'

require_relative '../config/pony'
require_relative '../config/pdf_engine'
require_relative '../config/exception_tracker'
require_relative '../config/pagination'
require_relative '../config/development' if ENV['DEVELOPMENT']

require_relative 'concerns/install'
require_relative 'models/charity'
require_relative 'models/product'
require_relative 'models/donation'
require_relative 'routes/charity'
require_relative 'routes/products'
require_relative 'routes/webhooks'
require_relative 'routes/gdpr'

require_relative 'utils/donation_service'
require_relative 'utils/email_service'
require_relative 'utils/render_pdf'
require_relative 'utils/export_csv'

class SinatraApp < Sinatra::Base
  register Sinatra::Shopify
  set :scope, 'read_products, read_orders'

  register Kaminari::Helpers::SinatraHelpers

  # Home page
  get '/' do
    shopify_session do
      @shop = ShopifyAPI::Shop.current
      @charity = Charity.find_by(shop: current_shop_name)
      @products = Product.where(shop: current_shop_name).page(params[:products_page])
      @donations = Donation.where(shop: current_shop_name).order('created_at DESC').page(params[:donations_page])
      @tab = params[:tab] || 'products'
      erb :home
    end
  end

  # Help page
  get '/help' do
    erb :help
  end

  # order/paid webhook receiver
  post '/order.json' do
    webhook_session do |order|
      return unless order['customer']
      return unless order['customer']['email']

      donations = donations_from_order(current_shop_name, order)

      unless donations.empty?
        charity = Charity.find_by(shop: current_shop_name)
        shopify_shop = ShopifyAPI::Shop.current
        donation_amount = sprintf( "%0.02f", donations.sum)

        if donation = save_donation(current_shop_name, order, donation_amount)
          receipt_pdf = render_pdf(shopify_shop, charity, donation)
          deliver_donation_receipt(shopify_shop, charity, donation, receipt_pdf)
        end
      end
    end
  end

  # resend a donation receipt
  post '/resend' do
    shopify_session do
      donation = Donation.find_by(shop: current_shop_name, id: params['id'])
      charity = Charity.find_by(shop: current_shop_name)
      shopify_shop = ShopifyAPI::Shop.current

      unless donation.void
        receipt_pdf = render_pdf(shopify_shop, charity, donation)
        deliver_donation_receipt(shopify_shop, charity, donation, receipt_pdf)
        flash[:notice] = "Email resent!"
      else
        flash[:error] = "Donation is void"
      end

      redirect '/'
    end
  end

  post '/void' do
    shopify_session do
      donation = Donation.find_by(shop: current_shop_name, id: params['id'])
      charity = Charity.find_by(shop: current_shop_name)
      shopify_shop = ShopifyAPI::Shop.current

      donation.update({void: true})

      flash[:notice] = "Donation voided"
      redirect '/'
    end
  end

  # render a preview of user edited email template
  get '/preview_email' do
    shopify_session do
      charity = Charity.find_by(shop: current_shop_name)
      subject = params['subject']
      template = params['template']
      body = email_body(charity, mock_donation)

      {email_subject: subject, email_body: body, email_template: template}.to_json
    end
  end

  # render a preview of the user edited pdf template
  get '/preview_pdf' do
    shopify_session do
      charity = Charity.find_by(shop: current_shop_name)
      shopify_shop = ShopifyAPI::Shop.current
      donation = mock_donation

      receipt_pdf = render_pdf(shopify_shop, charity, donation)
      content_type 'application/pdf'
      receipt_pdf
    end
  end

  # send a test email to the user
  get '/test_email' do
    shopify_session do
      charity = Charity.find_by(shop: current_shop_name)
      shopify_shop = ShopifyAPI::Shop.current
      donation = mock_donation

      receipt_pdf = render_pdf(shopify_shop, charity, donation)
      deliver_donation_receipt(shopify_shop, charity, donation, receipt_pdf, params['to'])

      status 200
    end
  end

  # export donations
  post '/export' do
    shopify_session do
      start_date = Date.parse(params['start_date'])
      end_date = Date.parse(params['end_date'])

      csv = export_csv(current_shop_name, start_date, end_date)
      attachment   'donations.csv'
      content_type 'application/csv'
      csv
    end
  end

  private

  def mock_donation
    mock_order = JSON.parse( File.read(File.join('test', 'fixtures/order_webhook.json')) )
    build_donation(current_shop_name, mock_order, 20.00)
  end
end
