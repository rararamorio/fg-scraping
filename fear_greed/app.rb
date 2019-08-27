# require 'httparty'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'google_drive'
require 'fcm'

class FearGreed
  def initialize(url)
    @url = url
    json_file = ENV['JSON']
    options = JSON.parse(File.read(json_file))
    key = OpenSSL::PKey::RSA.new(options['private_key'])
    auth = Signet::OAuth2::Client.new(
      token_credential_uri: options['token_uri'],
      audience: options['token_uri'],
      scope: [
        'https://www.googleapis.com/auth/drive',
        'https://docs.google.com/feeds/',
        'https://docs.googleusercontent.com/',
        'https://spreadsheets.google.com/feeds/',
      ],
      issuer: options['client_email'],
      signing_key: key
    )
    auth.fetch_access_token!
    @session = GoogleDrive.login_with_oauth(auth.access_token)
    @ws = @session.spreadsheet_by_key(ENV['SPREADSHEET']).worksheets[0]
    @user_ws = @session.spreadsheet_by_key(ENV['SPREADSHEET']).worksheets[1]
    @histories = @session.spreadsheet_by_key(ENV['SPREADSHEET']).worksheets[2]
  end

  def scraping()
    charset = nil
    html = open(@url) do |f|
      charset = f.charset
      f.read
    end

    doc = Nokogiri::HTML.parse(html, nil, charset)
    fgvalue = nil
    doc.xpath('//*[@id="needleChart"]/ul/li[1]').each do |node|
      fgvalue = node.inner_text.match(/Fear & Greed Now: (\d+?) \(Extreme Fear\)/)[1]
    end
    return if fgvalue.nil?

    1.step do |i|
      history = @histories[i, 1]
      if history.nil? || history == ''
        @histories[i, 1] = Time.new
        @histories[i, 2] = fgvalue
        @histories.save
        break
      end
    end

    fgvalue.to_i
  end

  def check(fg)
    result = false
    if fg < 21
      ago_fg = load
      if ago_fg.nil?
        result =  true
      else
        result =  true if ago_fg > fg
      end
    end
    save(fg)
    result
  end

  def load()
    val = @ws[1, 1]
    return nil if val.nil? || val == ''

    val.to_i
  end

  def save(fg)
    @ws[1, 1] = fg
    @ws.save
    p 'save complete'
  end

  def tokens()
    user_list = []
    1.step do |i|
      user = @user_ws[i, 1]
      break if user.nil? || user == ''

      user_list.push(user)
    end
    user_list
  end

  def push(fg)
    return unless check(fg)

    result = []
    fcm = FCM.new(ENV['FCM'])
    tokens().each do |token|
      opts = {
        'notification': {
          'title': 'Fear & Greed速報',
          'body': format('Fear & Greed Index %d になりました', fg)
        }
      }
      result.push(fcm.send_with_notification_key(token, opts))
    end
    result
  end
end

def lambda_handler(event:, context:)
  # Fear & Greed
  url = 'https://money.cnn.com/data/fear-and-greed/'
  fear_greed = FearGreed.new(url)
  fg = fearGreed.scraping
  fear_greed.push(fg)
  {
    statusCode: 200,
    body: {
      message: 'execute'
    }.to_json
  }
end
