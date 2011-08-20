select answers.answered_question_id
  from answers
  left join questions 
  ON questions.id = answers.answered_question_id
  where answers.user_id != 1; 
