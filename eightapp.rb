require "rubygems"
require "sinatra"
require "sqlite3"
require "dm-core"
require "dm-timestamps"
require "dm-migrations"

configure :development do
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
  if params [:ask][:question_txt].empty?
	    redirect '/ask'
	else
		@question = Question.new(params[:ask]) 
     
    if @question.save
      redirect "/question/#{@question.id}" 
    else
      redirect 'ask'
    end 
	end
end


# View Questions and answer Yes or No

get '/question/:id' do 
  @question = Question.get(params[:id])
  if @question
    erb :show
  else
    redirect('/list')
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
      redirect('question/:id')
  else
    redirect('list')
  end
end

# View a list of unanswered questions
get '/list' do

end


# A Simple page detailing what page redirect
# which says that the question was posted
get '/question_posted' do

end
