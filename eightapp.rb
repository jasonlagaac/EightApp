require "rubygems"
require "sinatra"
require "sqlite3"
require 'will_paginate'
require 'will_paginate/data_mapper'
require "dm-core"
require "dm-timestamps"
require "dm-migrations"
require "dm-validations"
require "twitter_oauth"

# Initial Configuration #
#########################
configure :development do
  set :sessions, true
  DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/eightapp.db")
  @@config = YAML.load_file("config.yml") rescue nil || {}
end


# User Class #
##############
class User
  include DataMapper::Resource

  property :id,           Serial
  property :twitter_id,   Integer, :key => true
  property :access_token, String, :length => 128 
  property :secret_token, String, :length => 128
  
  has n,  :questions
  has n,  :answers
end


# Question Class #
##################
class Question
  include DataMapper::Resource

  property :id,           Serial
  property :question_txt, String,   :length => 140, :required => true
  property :vote_yes,     Integer,  :default => 0
  property :vote_no,      Integer,  :default => 0

  belongs_to :user

end

# Answer Class #
################
class Answer
  include DataMapper::Resource
  
  property :id,   Serial
  property :answered_question_id,   Integer
  
  belongs_to :user  

end

# Create the database schema #
##############################
configure :development do
  DataMapper.auto_upgrade!
end


# Setup OAuth Authentication with Twitter 
# courtesy of Moomerman and Sinitter      
before do
  next if request.path_info =~ /ping$/
  @user = session[:user]
  @client = TwitterOAuth::Client.new(
    :consumer_key => ENV['CONSUMER_KEY'] || @@config['consumer_key'],
    :consumer_secret => ENV['CONSUMER_SECRET'] || @@config['consumer_secret'],
    :token => session[:access_token],
    :secret => session[:secret_token]
  )

  @rate_limit_status = @client.rate_limit_status
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

  # Saved Answered Question 
  def answered_question(uid, qid) 
    answer = Answer.new
    answer.user_id = uid
    answer.answered_question_id = qid

    if answer.save
      return true
    else
      return false
    end
  end

  # Obtain list of un-answered questions
  def questions_list( uid )
    repository(:default).adapter.query(
      "SELECT questions.id FROM questions
       WHERE  questions.user_twitter_id != #{uid}"
    )
  end

  # Obtain a list of answered questions 
  def get_answered_questions( uid )
    repository(:default).adapter.query(
      "SELECT answers.answered_question_id FROM answers
       WHERE user_twitter_id = #{uid}"
    )
  end

  # Get a single unanswered question
  def get_unanswered_question( uid )
    answered_questions = get_answered_questions( uid )
    questions = questions_list( uid )

    result = questions - answered_questions
    return result.first
  end

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

# Answer a Question #
#####################
get '/answer' do
  if @client.authorized?
    @question = Question.get(get_unanswered_question(get_twitter_uid))
  
    erb :answer
  else
    redirect '/'
  end
end

post '/answer' do
  if @client.authorized?
    @question = Question.get(get_unanswered_question(get_twitter_uid))
 
    if @question 
      if (params[:post][:answer] == 'yes')
        @question.vote_yes += 1
        @question.save
        answered_question(user_id, question.uid)
      elsif (params[:post][:answer] == 'no')
        @question.vote_no += 1
        @question.save
        answered_question(user_id, question.id)
      else
        redirect '/answer'
      end
    else
      redirect '/'
    end  
  else
    redirect '/'
  end
end

# View Questions #
##################
get '/view_question/:id' do 
  @question = Question.get(params[:id])
  
  if @question
    erb :view_question
  else
    redirect '/'
  end
end

# View a list of questions
get '/my_questions' do
  if @client.authorized?
    @questions = Question.paginate(:user_twitter_id => get_twitter_uid, 
                                   :page => params[:page], :per_page => 5)
    erb :my_questions
  else
    redirect '/'
  end
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

  if @client.authorized?
    session[:access_token] = @access_token.token
    session[:secret_token] = @access_token.secret
    session[:user] = true
    
    if !User.all(:twitter_id => get_twitter_uid)
      new_user = User.new(
                    :twitter_id => get_twitter_uid, 
                    :access_token => @access_token.token, 
                    :secret_token => @access_token.secret
              )
      new_user.save
    end
  end

  redirect '/'
end