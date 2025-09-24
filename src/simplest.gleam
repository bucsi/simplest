import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import lustre/attribute
import lustre/element
import lustre/event.{on_click}

import plinth/javascript/storage
import varasto

import lustre
import lustre/element/html.{div, hr, li, section, ul}

import plinth/javascript/console

const key = "net.bucsi.simplest.tasks"

const localstorage_set_failure = "LocalStorage.set failed!"

pub type Task {
  Task(id: String, description: String)
}

fn task_to_json(task: Task) -> json.Json {
  let Task(id:, description:) = task
  json.object([
    #("id", json.string(id)),
    #("description", json.string(description)),
  ])
}

fn task_decoder() -> decode.Decoder(Task) {
  use id <- decode.field("id", decode.string)
  use description <- decode.field("description", decode.string)
  decode.success(Task(id:, description:))
}

pub type Tasks {
  Tasks(do: Dict(String, Task), done: Dict(String, Task))
}

fn tasks_to_json(tasks: Tasks) -> json.Json {
  let Tasks(do:, done:) = tasks
  json.object([
    #("do", json.dict(do, fn(string) { string }, task_to_json)),
    #("done", json.dict(done, fn(string) { string }, task_to_json)),
  ])
}

fn tasks_decoder() -> decode.Decoder(Tasks) {
  use do <- decode.field("do", decode.dict(decode.string, task_decoder()))
  use done <- decode.field("done", decode.dict(decode.string, task_decoder()))
  decode.success(Tasks(do:, done:))
}

pub type Message {
  UserClickedDoTask(id: String)
  UserClickedDoneTask(id: String)
}

pub type Model {
  Model(
    load: fn() -> Result(Tasks, varasto.ReadError),
    save: fn(Tasks) -> Tasks,
    tasks: Tasks,
  )
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_flags: a) -> Model {
  let assert Ok(local) = storage.local()
  let typed_storage = varasto.new(local, tasks_decoder(), tasks_to_json)

  let load = fn() { typed_storage |> varasto.get(key) }
  let save = fn(value) {
    case varasto.set(typed_storage, key, value) {
      Ok(_) -> value
      Error(_) -> {
        console.error(localstorage_set_failure)
        panic as localstorage_set_failure
      }
    }
  }

  let tasks = case load() {
    Ok(value) -> value
    Error(_) -> save(Tasks(dict.new(), dict.new()))
  }

  Model(load:, save:, tasks:)
}

fn update(model: Model, msg: Message) -> Model {
  case msg {
    UserClickedDoTask(id:) -> move_do_task_to_done(model, id)
    UserClickedDoneTask(id:) -> move_done_task_to_do(model, id)
  }
}

fn move_done_task_to_do(model: Model, id: String) -> Model {
  console.log("move_done_task_to_do: " <> id)
  let Tasks(do:, done:) = model.tasks

  let assert Ok(task) = done |> dict.get(id)
  let do = do |> dict.insert(id, task)
  let done = done |> dict.delete(id)
  let tasks = Tasks(do:, done:) |> model.save

  Model(..model, tasks:)
}

fn move_do_task_to_done(model: Model, id: String) -> Model {
  console.log("move_do_task_to_done: " <> id)
  let Tasks(do:, done:) = model.tasks

  let assert Ok(task) = do |> dict.get(id)
  let done = done |> dict.insert(id, task)
  let do = do |> dict.delete(id)
  let tasks = Tasks(do:, done:) |> model.save

  Model(..model, tasks:)
}

fn view(model: Model) {
  let Tasks(do:, done:) = model.tasks
  div([], [
    section([], [
      ul([], list.map(dict.values(do), do_task_to_li)),
    ]),
    hr([]),
    section([], [
      ul([], list.map(dict.values(done), done_task_to_li)),
    ]),
  ])
}

fn do_task_to_li(task: Task) -> element.Element(Message) {
  let Task(id:, description:) = task

  li([on_click(UserClickedDoTask(id))], [html.text(description)])
}

fn done_task_to_li(task: Task) -> element.Element(Message) {
  let Task(id:, description:) = task

  li([on_click(UserClickedDoneTask(id))], [html.text(description)])
}
