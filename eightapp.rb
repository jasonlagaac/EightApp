require "rubygems"
require "sinatra"
require 'will_paginate'
require 'will_paginate/data_mapper'
require "dm-core"
require "dm-timestamps"
require "dm-migrations"
require "dm-validations"
require "dm-postgres-adapter"
require "twitter_oauth"
require "googl"

# Initial Configuration #
#########################
configure :development do
  set :sessions, true
  DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/eightapp.db")
  @@config = YAML.load_file("config.yml") rescue nil || {}
end

configure :production do
  set :sessions, true
  DataMapper.setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/mydb')
end


# User Class #
##############
class User
  include DataMapper::Resource

  property :id,           Serial
  property :twitter_id,   Integer,  :key => true
  property :username,     String,   :length => 128
  property :access_token, String,   :length => 128 
  property :secret_token, String,   :length => 128
  
  has n,  :questions
end


# Question Class #
##################
class Question
  include DataMapper::Resource

  property :id,           Serial
  property :question_txt, String,   :length => 140, :required => true
  property :created_at,   DateTime
  property :vote_yes,     Integer,  :default => 0
  property :vote_no,      Integer,  :default => 0

  belongs_to :user

end


# Create the database schema #
##############################
configure do
  DataMapper.auto_upgrade!
end


# Setup OAuth Authentication with Twitter 
# courtesy of Moomerman and Sinitter      
before do
  next if request.path_info =~ /ping$/
  @client = TwitterOAuth::Client.new(
    :consumer_key => ENV['CONSUMER_KEY'] || @@config['consumer_key'],
    :consumer_secret => ENV['CONSUMER_SECRET'] || @@config['consumer_secret'],
    :token => session[:access_token],
    :secret => session[:secret_token]
  )

  @rate_limit_status = @client.rate_limit_status
end

# View Index Page
get '/' do
  erb :index
end

# Ask a Question #
##################
get '/ask' do
  if @client.authorized?
	  @title = "Ask a Question"
	  erb :ask
	else
	  redirect '/'
	end
end

post '/ask' do
  if @client.authorized?
    if params[:post][:question_txt].empty?      
	      redirect '/ask'
    else
        new_question = Question.new(params[:post])
        current_user = User.first(:twitter_id => get_twitter_uid)
        new_question.user_id = current_user.id
        new_question.user_twitter_id = current_user.twitter_id
        
        if new_question.save
          redirect "/question_posted" 
        else          
            puts "#{new_question.question_txt}\n #{new_question.user_id}"          
          redirect '/ask'
        end 
    end
  else
    redirect '/'
  end
end

# A Simple page detailing what page redirect
# which says that the question was posted
get '/question_posted' do
  if @client.authorized?
    user = User.first(:twitter_id => get_twitter_uid)
    @question = Question.last(:user_id => user.id)
    erb :question_posted
  else
    redirect '/'
  end
end

# Share the posted question amongst followers
get '/question_posted/share' do
  if @client.authorized?
    user = User.first(:twitter_id => get_twitter_uid)
    question = Question.last(:user_id => user.id)
    url = Googl.shorten("http://eightapp.safetyscissors.co/view_question/#{question.id}")
    message = "I asked \"#{question.question_txt}\" on eight #{url.short_url} #eightapp"
    @client.update(message)
  end
  
  redirect '/my_questions'
end

# Answer a Question #
#####################
get '/answer' do
    if @client.authorized? 
      @question = Question.get(get_random_question_not_own_user)
    else
      @question = Question.get(get_random_question)
    end
    
    erb :answer
end

post '/answer/:id' do

    @question = Question.get(:id)
 
    if @question 
      if (params[:post][:answer] == 'yes')
        @question.vote_yes += 1
        @question.save
      elsif (params[:post][:answer] == 'no')
        @question.vote_no += 1
        @question.save
      else
        redirect '/answer'
      end
    else
      redirect '/'
    end  
    
    redirect '/answer'
end

# View Questions #
##################
get '/view_question/:id' do 
  @question = Question.get(params[:id])
  
  if !@question.nil?
    erb :view_question
  else
    redirect '/'
  end
end

# View a list of questions
get '/my_questions' do
  if @client.authorized?
    @questions = Question.paginate(:user_twitter_id => get_twitter_uid, 
                                   :page => params[:page], 
                                   :per_page => 5, 
                                   :order => [:created_at.desc]
                                  )
    erb :my_questions
  else
    redirect '/'
  end
end

get '/list' do
  @questions = Question.paginate(:page => params[:page], :per_page => 10,:order => [:created_at.desc])
  erb :list
end



# Twitter Authentication Actions #
##################################
get '/connect' do
  request_token = @client.request_token(
    :oauth_callback => ENV['CALLBACK_URL'] || @@config['callback_url']
  )
  session[:request_token] = request_token.token
  session[:request_token_secret] = request_token.secret
  redirect request_token.authorize_url.gsub('authorize', 'authenticate')
end

# Twitter OAuth Callback URL handling
# and store the user's tokens in the database
get '/auth' do
  begin
    @access_token = @client.authorize(
      session[:request_token],
      session[:request_token_secret],
      :oauth_verifier => params[:oauth_verifier]
    )
  rescue OAuth::Unauthorized
  end


  session[:access_token] = @access_token.token
  session[:secret_token] = @access_token.secret
  session[:user] = true
    
  puts get_twitter_username
  
  if @client.authorized?
      new_user = User.new(
                    :twitter_id => get_twitter_uid,
                    :username => get_twitter_username, 
                    :access_token => @access_token.token, 
                    :secret_token => @access_token.secret
              )
      new_user.save if User.all(:twitter_id => get_twitter_uid).empty?
  end

  redirect '/'
end

get '/signout' do
  session[:user] = nil
  session[:request_token] = nil
  session[:request_token_secret] = nil
  session[:access_token] = nil
  session[:secret_token] = nil
  session.clear
  
  redirect '/'
end

# General Helpers #
###################
helpers do
  # Obtain twitter user id
  def get_twitter_uid
    if @client.authorized?
        user_data = @client.info
        return user_data['id']
    end

    return nil
  end
  
  def get_twitter_username
    if @client.authorized?
      user_data = @client.info
      return user_data['screen_name']
    end
    
    return nil
  end
  
  def get_random_question
    repository(:default).adapter.query(
      "SELECT id FROM questions
      ORDER BY RANDOM()
      LIMIT 1"
    )
  end
  
  def get_random_question_not_own_user
    repository(:default).adapter.query(
      "SELECT id FROM questions
      ORDER BY RANDOM()
      LIMIT 1 WHERE user_twitter_id != #{get_twitter_uid}"
    )
  end
end
