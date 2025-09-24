import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

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
  Task(id: Int, description: String)
}

fn task_to_json(task: Task) -> json.Json {
  let Task(id:, description:) = task
  json.object([
    #("id", json.int(id)),
    #("description", json.string(description)),
  ])
}

fn task_decoder() -> decode.Decoder(Task) {
  use id <- decode.field("id", decode.int)
  use description <- decode.field("description", decode.string)
  decode.success(Task(id:, description:))
}

pub type Tasks {
  Tasks(do: Dict(Int, Task), done: Dict(Int, Task))
}

fn tasks_to_json(tasks: Tasks) -> json.Json {
  let Tasks(do:, done:) = tasks
  json.object([
    #("do", json.dict(do, int.to_string, task_to_json)),
    #("done", json.dict(done, int.to_string, task_to_json)),
  ])
}

fn tasks_decoder() -> decode.Decoder(Tasks) {
  use do <- decode.field(
    "do",
    decode.dict(string_to_int_decoder(), task_decoder()),
  )
  use done <- decode.field(
    "done",
    decode.dict(string_to_int_decoder(), task_decoder()),
  )
  decode.success(Tasks(do:, done:))
}

fn string_to_int_decoder() -> decode.Decoder(Int) {
  use value <- decode.then(decode.string)
  case int.parse(value) {
    Ok(v) -> decode.success(v)
    Error(_) -> decode.failure(0, "Expected a string representing an Int")
  }
}

pub type Message {
  UserClickedDoTask(id: Int)
  UserClickedDoneTask(id: Int)
  UserUpdatedCurrentlyEditedTask(currently_edited_task: String)
  UserSavedCurrentlyEditedTask
}

pub type NewTaskData {
  NewTaskData(description: String)
}

pub type Model {
  Model(save: fn(Tasks) -> Tasks, tasks: Tasks, currently_edited_task: String)
}

pub fn main() {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

fn init(_flags: a) -> Model {
  let assert Ok(local) = storage.local()
  let typed_storage = varasto.new(local, tasks_decoder(), tasks_to_json)

  let save = fn(value: Tasks) -> Tasks {
    case varasto.set(typed_storage, key, value) {
      Ok(_) -> value
      Error(_) -> {
        console.error(localstorage_set_failure)
        console.log(value |> tasks_to_json |> json.to_string)
        panic as localstorage_set_failure
      }
    }
  }

  let tasks = case typed_storage |> varasto.get(key) {
    Ok(value) -> value
    Error(_) -> {
      console.debug("No saved tasks found, starting fresh.")
      save(Tasks(dict.new(), dict.new()))
    }
  }

  Model(save:, tasks:, currently_edited_task: "")
}

fn update(model: Model, msg: Message) -> Model {
  case msg {
    UserClickedDoTask(id:) -> move_do_task_to_done(model, id)
    UserClickedDoneTask(id:) -> move_done_task_to_do(model, id)
    UserUpdatedCurrentlyEditedTask(currently_edited_task:) ->
      Model(..model, currently_edited_task:)
    UserSavedCurrentlyEditedTask -> add_task(model)
  }
}

fn move_done_task_to_do(model: Model, id: Int) -> Model {
  let Tasks(do:, done:) = model.tasks

  let assert Ok(task) = done |> dict.get(id)
  let do = do |> dict.insert(id, task)
  let done = done |> dict.delete(id)
  let tasks = Tasks(do:, done:) |> model.save

  Model(..model, tasks:)
}

fn move_do_task_to_done(model: Model, id: Int) -> Model {
  let Tasks(do:, done:) = model.tasks

  let assert Ok(task) = do |> dict.get(id)
  let done = done |> dict.insert(id, task)
  let do = do |> dict.delete(id)
  let tasks = Tasks(do:, done:) |> model.save

  Model(..model, tasks:)
}

fn add_task(model: Model) -> Model {
  let Tasks(do:, done:) = model.tasks

  let id =
    int.max(
      do |> dict.keys |> list.max(int.compare) |> result.unwrap(0),
      done |> dict.keys |> list.max(int.compare) |> result.unwrap(0),
    )
    + 1

  let task = Task(id:, description: model.currently_edited_task)
  let do = do |> dict.insert(id, task)
  let tasks = Tasks(do:, done:) |> model.save

  Model(..model, tasks:, currently_edited_task: "")
}

fn view(model: Model) {
  let Tasks(do:, done:) = model.tasks
  div([], [
    section([], [
      html.input([
        attribute.value(model.currently_edited_task),
        event.on_input(UserUpdatedCurrentlyEditedTask),
      ]),
      html.button(
        [
          on_click(UserSavedCurrentlyEditedTask),
        ],
        [html.text("Add task")],
      ),
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
