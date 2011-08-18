require "rubygems"
require "sinatra"
require "sqlite3"
require "dm-core"
require "dm-timestamps"
require "dm-migrations"

configure :development do
  set :sessions, true
  set :test_uid,  1
  DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/eightapp.db")
end

class User
  include DataMapper::Resource

  property :id,           Serial
  property :username,     String, :length => 64
  
  has n,  :questions
  has n,  :answers
end

class Question
  include DataMapper::Resource

  property :id,           Serial
  property :question_txt, String,   :length => 140, :required => true
  property :created_at,   DateTime
  property :vote_yes,     Integer,  :default => 0
  property :vote_no,      Integer,  :default => 0

  belongs_to :user
end

class Answer
  include DataMapper::Resource
  
  property :id,   Serial
  property :answered_question_id,   Integer
  
  belongs_to :user  
end

configure :development do
  # Create or upgrade all tables instantly
  DataMapper.auto_upgrade!
end

# View Index Page / User's Own Questions
get '/' do

end

# Ask a Question
get '/ask' do
	@title = "Ask a Question"
  @authorized = nil
	erb :ask
end

post '/ask' do
  if params[:post][:question_txt].empty?
	    redirect '/ask'
	else
		@question = Question.new(params[:post])
    @question.user_id = 1

    if @question.save
      redirect "/question_posted" 
    else
      redirect '/ask'
    end 
	end
end


# View Questions and answer Yes or No
get '/question/:id' do 
  @question = Question.get(params[:id])
  if @question
    erb :show
  else
    redirect '/list'
  end
end

post '/question/:id' do
  @question = Question.get(params[:id])
  
  if @question
    if (params[:post][:answer] == 'yes')
      @question.yes += 1
    elsif (params[:post][:answer] == 'no')
      @question.no += 1 
    else
      redirect 'question/:id'
    end
  else
    redirect 'list'
  end
end

# View a list of unanswered questions
get '/list' do
  # Obtain a list of unanswered question by doing a 
  # join of the Answers table and the Questions table
  # and also excluding a user's own questions.
  @unanswered_questions = repository(:default).adapter.query(
    "SELECT questions.id FROM questions 
      LEFT OUTER JOIN answers ON questions.id = answers.answered_question_id
      WHERE answers.answered_question_id is null and questions.user_id != #{settings.test_uid}"
    )
  @unanswered_questions.first.to_s
end


# A Simple page detailing what page redirect
# which says that the question was posted
get '/question_posted' do
  @question = Question.last(:user_id => settings.test_uid)

  # Obtain the latest question from a specific user
  # and then post "You're question blah has been posted"
  @question.question_txt
end
