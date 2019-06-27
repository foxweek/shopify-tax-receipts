require "test_helper"

class ProductsTest < ActiveSupport::TestCase
  def app
    SinatraApp
  end

  setup do
    @shop = "apple.myshopify.com"
  end

  test "products admin link / product picker" do
    mock_shop_api_call
    mock_product_api_call(1)
    mock_product_api_call(2)

    assert_difference 'Product.count', +2 do
      get '/products', {ids: [1,2]}, 'rack.session' => session
      assert last_response.redirect?
    end
  end

  test "product admin link" do
    mock_shop_api_call
    mock_product_api_call(1)

    assert_difference 'Product.count', +1 do
      get '/product', {id: 1}, 'rack.session' => session
      assert last_response.redirect?
    end
  end

  test "products/update" do
    product_webhook = load_fixture 'product.json'
    shopify_product = JSON.parse(product_webhook)
    shopify_product['title'] = 'beans'

    product = Product.find_by(product_id: shopify_product['id'])
    product.update!({shopify_product: shopify_product.to_json})

    SinatraApp.any_instance.expects(:verify_shopify_webhook).returns(true)

    post '/product_update', product_webhook, 'HTTP_X_SHOPIFY_SHOP_DOMAIN' => @shop

    assert last_response.ok?
    assert_equal 'IPod Nano - 8GB', product.reload.title
  end

  private

  def session
    { shopify: {shop: @shop, token: 'token'} }
  end
end
