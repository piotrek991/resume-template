FROM ruby:3.3

WORKDIR /home/app

COPY Gemfile* ./

RUN bundle install

COPY . .

EXPOSE 4000

CMD [ "bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0" ]
