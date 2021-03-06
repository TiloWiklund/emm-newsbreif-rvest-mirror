## MIT License
## Copyright (c) 2020 Tilo Wiklund
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
## SOFTWARE.

library(magrittr)
library(tidyverse)
library(rvest)
library(fs)

DATE <- "2020-05-01"
LANGUAGE <- "sv"
BASE_OUTPUT_PATH <- "/tmp"

emm.url.template <- function(i, from, to=from, language="all", page.language="en")
  str_c("https://emm.newsbrief.eu/NewsBrief/dynamic",
        "?language=", page.language,
        "&page=", i,
        "&edition=searcharticles&option=advanced",
        "&dateFrom=", from,
        "&dateTo=", to,
        "&lang=", language)

general.file.template <- function(type, i, from, to=from, language="all") {
  date_block <- if(from == to) from else str_c(from, "--", to)
  file_name <- str_c(type, "-", language, "-", date_block, "-", curr_page, ".csv.gz")
  fs::path(BASE_OUTPUT_PATH, file_name)
}

articles.file.template <- function(i, from, to=from, language="all")
  general.file.template("articles", i, from, to, language)

entities.file.template <- function(i, from, to=from, language="all")
  general.file.template("entities", i, from, to, language)

categories.file.template <- function(i, from, to=from, language="all")
  general.file.template("categories", i, from, to, language)

get_page_count <- function(doc)
  doc %>%
    html_node(xpath="//input[@name = 'page_count']") %>%
    html_attr("value") %>%
    as.numeric()

get_current_page <- function(doc)
  doc %>%
    html_node(xpath="//input[@name = 'current_page']") %>%
    html_attr("value") %>%
    as.numeric()

has_class <- function(tags, cls)
  tags %>%
    html_attr("class") %>%
    str_detect(str_c("(^| )", cls, "( |$)"))

parse_categories <- function(doc) {
  doc %>%
    html_nodes(xpath="./a[starts-with(@href, '/NewsBrief/alertedition')]") %>%
    html_attr("href") %>%
    str_match("/NewsBrief/alertedition/[a-zA-Z0-9]+/(.+)\\.html") %>%
    magrittr::extract(,2)
}

parse_entities <- function(doc) {
  doc %>%
    html_nodes(xpath="./a[starts-with(@href, '/NewsBrief/entityedition')]") %>%
    html_attr("href") %>%
    str_match("/NewsBrief/entityedition/[a-zA-Z0-9]+/([0-9]+)\\.html") %>%
    magrittr::extract(,2) %>%
    as.integer()
}

parse_page <- function(doc) {
  article.nodes <- doc %>%
    html_nodes(xpath="/html/body/div[contains(@class, 'articlebox_big')]")

  is.duplicate <- article.nodes %>%
    has_class("duplicate_article")

  headline.links.nodes <- article.nodes %>%
    html_node(xpath="./p[contains(@class, 'center_story') and contains(@class, 'center_headline_top')]/a[contains(@class, 'headline_link')]")

  url <- headline.links.nodes %>%
    html_attr("href")
  url.language <- headline.links.nodes %>%
    html_attr("lang")

  headline.source.nodes <- article.nodes %>%
    html_node(xpath="./p[contains(@class, 'center_headline_source')]")

  source.country <- headline.source.nodes %>%
    html_node(xpath="./img[@alt='Source country']") %>%
    html_attr("src") %>%
    str_match("/NewsBrief/web/flags/small/([A-Z]+)\\.gif") %>%
    magrittr::extract(,2)

  source.name <- headline.source.nodes %>%
    html_node(xpath="./a[1]") %>%
    html_text()

  leadin.nodes <- article.nodes %>%
    html_node(xpath="./p[contains(@class, 'center_leadin')]")

  leadin.language <- leadin.nodes %>%
    html_attr("lang")

  leadin <- leadin.nodes %>%
    html_text()

  more.nodes <- article.nodes %>%
    html_node(xpath="./div[contains(@class, 'alert_more')]")

  entity.lists <- more.nodes %>%
    html_node(xpath="./p[contains(@class, 'center_also') and starts-with(., 'Entities:')]") %>%
    map(parse_entities)

  category.lists <- more.nodes %>%
    html_node(xpath="./p[contains(@class, 'center_also') and starts-with(., 'Other categories:')]") %>%
    map(parse_categories)

  articles <- tibble(source.name, source.country,
                     is.duplicate, url, url.language, leadin, leadin.language)

  entities <- tibble(url = url, entity = entity.lists) %>%
    unnest(one_of("entity"))

  categories <- tibble(url = url, category = category.lists) %>%
    unnest(one_of("category"))

  list(articles=articles, entities=entities, categories=categories)
}

dump_parsed <- function(i, parse_results) {
  write_csv(parse_results$articles,
            articles.file.template(i, DATE, language=LANGUAGE))
  write_csv(parse_results$entities,
            entities.file.template(i, DATE, language=LANGUAGE))
  write_csv(parse_results$categories, categories.file.template(i, DATE))
}

page <- read_html(emm.url.template(1, DATE, language=LANGUAGE))

## Theory:
## page_count ==  0 if no search results
## page_count == -1 if more pages available
## page_count == -2 if on last page
## page_count == -3 if past last page
page_count <- get_page_count(page)
curr_page <- get_current_page(page)

max_page_count <- 500

if(page_count != 0) {
  print(curr_page)
  dump_parsed(curr_page, parse_page(page))
} else {
  warning("No search results!")
}

while(page_count == -1 && curr_page <= max_page_count) {
  page <- read_html(emm.url.template(curr_page + 1, DATE, language=LANGUAGE))
  print(curr_page + 1)
  page_count <- get_page_count(page)
  curr_page <- get_current_page(page)
  ##
  dump_parsed(curr_page, parse_page(page))
}


## search_page <- read_html("https://emm.newsbrief.eu/NewsBrief/search/en/advanced.html")

