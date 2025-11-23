class ToDoList:
    def __init__(self):
        self.tasks = []

    def add_task(self, task: str):
        self.tasks.append(task)

    def show_tasks(self):
        if not self.tasks:
            print("No tasks yet!")
            return
        print("Your Tasks:")
        for i, task in enumerate(self.tasks, start=1):
            print(f"{i}. {task}")

if __name__ == "__main__":
    todo = ToDoList()
    todo.add_task("Buy groceries")
    todo.add_task("Finish Python project")
    todo.show_tasks()
