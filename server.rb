require 'sinatra'
require 'pry'
require 'pg'

def db_conn
  begin
    connection = PG.connect(dbname: 'movies')

    yield(connection)

  ensure
    connection.close
  end
end

def get_movies_by_title
  db_conn do |conn|
    conn.exec('SELECT movies.id AS id, movies.title AS Title, movies.year
              AS Year, movies.rating AS Rating, genres.name
              AS Genre, studios.name AS Studio FROM movies
              JOIN genres ON genres.id = movies.genre_id
              LEFT OUTER JOIN studios ON studios.id = movies.studio_id
              ORDER BY movies.title')
  end.to_a
end

def get_movies_by_year
  db_conn do |conn|
    conn.exec('SELECT movies.id AS id, movies.title AS Title, movies.year
              AS Year, movies.rating AS Rating, genres.name
              AS Genre, studios.name AS Studio FROM movies
              JOIN genres ON genres.id = movies.genre_id
              LEFT OUTER JOIN studios ON studios.id = movies.studio_id
              ORDER BY movies.year DESC, movies.title')
  end.to_a
end


def get_movies_by_rating
  db_conn do |conn|
    conn.exec('SELECT movies.id AS id, movies.title AS Title, movies.year
              AS Year, movies.rating AS Rating, genres.name
              AS Genre, studios.name AS Studio FROM movies
              JOIN genres ON genres.id = movies.genre_id
              LEFT OUTER JOIN studios ON studios.id = movies.studio_id
              ORDER BY movies.rating DESC, movies.title')
  end.to_a
end

def get_movies_by_title_paginated(page_number)
  db_conn do |conn|
    conn.exec('SELECT movies.id AS id, movies.title AS Title, movies.year
              AS Year, movies.rating AS Rating, genres.name
              AS Genre, studios.name AS Studio FROM movies
              JOIN genres ON genres.id = movies.genre_id
              LEFT OUTER JOIN studios ON studios.id = movies.studio_id
              ORDER BY movies.title
              LIMIT 20 OFFSET $1', [(page_number - 1) * 20])
  end.to_a
end

def get_movies_by_year_paginated(page_number)
  db_conn do |conn|
    conn.exec('SELECT movies.id AS id, movies.title AS Title, movies.year
              AS Year, movies.rating AS Rating, genres.name
              AS Genre, studios.name AS Studio FROM movies
              JOIN genres ON genres.id = movies.genre_id
              LEFT OUTER JOIN studios ON studios.id = movies.studio_id
              ORDER BY movies.year DESC, movies.title
              LIMIT 20 OFFSET $1', [(page_number - 1) * 20])
  end.to_a
end

def get_movies_by_rating_paginated(page_number)
  db_conn do |conn|
    conn.exec_params('SELECT movies.id AS id, movies.title AS Title, movies.year
              AS Year, movies.rating AS Rating, genres.name
              AS Genre, studios.name AS Studio FROM movies
              JOIN genres ON genres.id = movies.genre_id
              LEFT OUTER JOIN studios ON studios.id = movies.studio_id
              ORDER BY movies.rating DESC, movies.title
              LIMIT 20 OFFSET $1', [(page_number - 1) * 20])
  end.to_a
end

def movie_title_search(query)
  db_conn do |conn|
    conn.exec_params('SELECT * FROM movies
                      WHERE to_tsvector(title) @@ plainto_tsquery($1)
                      OR to_tsvector(synopsis) @@ plainto_tsquery($1)',
                      [query])
  end.to_a
end

def get_all_actors
  db_conn do |conn|
    conn.exec('SELECT actors.id AS id, actors.name AS Name
              FROM actors ORDER BY actors.name')
  end.to_a
end

def get_info_for_actor(actor_id)
  db_conn do |conn|
    conn.exec_params("SELECT actors.name AS name, cast_members.character AS Character,
              movies.id AS movie_id, movies.title AS Title FROM actors
              JOIN cast_members ON cast_members.actor_id = actors.id
              JOIN movies ON cast_members.movie_id = movies.id
              WHERE actors.id = $1
              ORDER BY movies.title", [actor_id])
  end.to_a
end

def get_actor_name(actor_id)
  db_conn do |conn|
    conn.exec_params("SELECT actors.name AS name
                    FROM actors
                    WHERE actors.id = $1", [actor_id])
  end.to_a[0]['name']
end

def search_for_actor_or_role(query)
  db_conn do |conn|
    conn.exec_params('SELECT actors.id AS id, actors.name AS Name
                      FROM actors
                      JOIN cast_members ON actors.id = cast_members.actor_id
                      WHERE to_tsvector(actors.name) @@ plainto_tsquery($1)
                      OR to_tsvector(cast_members.character) @@ plainto_tsquery($1)
                      ORDER BY actors.name',
                      [query])
  end.to_a
end


#### END OF METHODS

get '/movies' do
  @page = params[:page].to_i
  query = params[:query]

  if query != nil
    @arr_of_movies = movie_title_search(query)
  elsif @page <= 0
    if params[:order] == 'year'
      @arr_of_movies = get_movies_by_year
    elsif params[:order] == 'rating'
      @arr_of_movies = get_movies_by_rating
    else
      @arr_of_movies = get_movies_by_title
    end

  else @page > 0
    @ol_start = ((@page - 1) * 20) + 1
    if params[:order] == 'year'
      @arr_of_movies = get_movies_by_year_paginated(@page)
    elsif params[:order] == 'rating'
      @arr_of_movies = get_movies_by_rating_paginated(@page)
    else
      @arr_of_movies = get_movies_by_title_paginated(@page)
    end
  end
  erb :'movies/movies_index'
end

get '/actors' do
  @query = params[:query]
  if @query != nil
    @arr_of_actors = search_for_actor_or_role(@query)
  else
    @arr_of_actors = get_all_actors
  end
  erb :'actors/actors_index'
end

get '/actors/:id' do
  actor_id = params[:id]
  # I want the actors name, all the movies he/she played in, the character they player, and the movie id
  @actor_info = get_info_for_actor(actor_id)

  @actor_name = get_actor_name(actor_id)

  erb :'actors/actor_show'
end


get '/movies/:id' do
  @movie_id = params[:id]

  # First, get all the movie info. Then, get cast info in seperate data structure
  @movie_info = db_conn do |conn|
    conn.exec_params("SELECT movies.title AS title, genres.name AS genre,
              studios.name AS studio, movies.synopsis AS synopsis FROM movies
              JOIN genres ON genres.id = movies.genre_id
              LEFT OUTER JOIN studios ON studios.id = movies.studio_id
              WHERE movies.id = $1", [@movie_id]
              )
  end.to_a

  #Get cast info
  @cast_info = db_conn do |conn|
  conn.exec("SELECT cast_members.character AS character,
            actors.name AS actor_name, actors.id AS actor_id FROM cast_members
            JOIN actors ON cast_members.actor_id = actors.id
            JOIN movies ON cast_members.movie_id = movies.id
            WHERE movies.id = #{@movie_id}"
            )
  end.to_a

  erb :'movies/movie_show'

end


