require "rubygems"
require "sinatra"
require "sqlite3"
require "dm-core"
require "dm-timestamps"
require "dm-migrations"

configure :development do
  set :test_uid,  2
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


helpers do
  def answered_question(uid, qid) 
    @answer = Answer.new
    @answer.user_id = uid
    @answer.answered_question_id = qid

    if @answer.save
      return true
    else
      return false
    end
  end

  def questions_list( uid )
    repository(:default).adapter.query(
      "SELECT questions.id FROM questions
       WHERE  questions.user_id != #{uid}"
    )
  end

  def get_answered_questions( uid )
    repository(:default).adapter.query(
      "SELECT answers.answered_question_id FROM answers
       WHERE user_id = #{uid}"
    )
  end

  def get_unanswered_question( uid )
    @answered_questions = get_answered_questions( uid )
    @questions = questions_list( uid )

    @result = @questions - @answered_questions
    return @result.first
  end

end

# View Index Page / User's Own Questions
get '/' do
  @authorized = true;
  erb :index
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
    @question.user_id = settings.test_uid 

    if @question.save
      redirect "/question_posted" 
    else
      redirect '/ask'
    end 
	end
end


# Answer a Question
get '/answer' do
  @question = Question.get(get_unanswered_question(settings.test_uid))

  erb :answer
end

post '/answer' do
  @question = Question.get(get_unanswered_question(settings.test_uid))
 
  if @question 
    if (params[:post][:answer] == 'yes')
      @question.vote_yes += 1
      @question.save
      answered_question(settings.test_uid, @question.id)
    elsif (params[:post][:answer] == 'no')
      @question.vote_no += 1
      @question.save
      answered_question(settings.test_uid, @question.id)
    else
      redirect '/answer'
    end
  else
    redirect '/'
  end  
  
  redirect '/answer'
end

# View Questions
get '/question/:id' do 
  @question = Question.get(params[:id])
  if @question
    erb :show
  else
    redirect '/list'
  end
end

# View a list of questions
get '/myquestions' do
  # Obtain a list of unanswered question by doing a 
  # join of the Answers table and the Questions table
  # and also excluding a user's own questions.
  #@questions = questions_list( settings.test_uid )
  erb :question;
end


# A Simple page detailing what page redirect
# which says that the question was posted
get '/question_posted' do
  @question = Question.last(:user_id => settings.test_uid)

  # Obtain the latest question from a specific user
  # and then post "You're question blah has been posted"
  erb :question_posted
end
