using Npgsql;

var builder = WebApplication.CreateBuilder(args);
var connectionString = builder.Configuration.GetConnectionString("Todos")
    ?? "Host=postgres;Port=5432;Database=todos;Username=todos;Password=todos-dev-only";
builder.Services.AddSingleton(_ => new NpgsqlDataSourceBuilder(connectionString).Build());

var app = builder.Build();
if (args.Contains("migrate"))
{
    if (Environment.GetEnvironmentVariable("FAIL_MIGRATION") == "1")
        throw new InvalidOperationException("Controlled migration failure before SQL execution.");
    await using var sql = typeof(Program).Assembly.GetManifestResourceStream("Api.Migration.sql")
        ?? throw new InvalidOperationException("Migration resource is missing.");
    using var reader = new StreamReader(sql);
    var db = app.Services.GetRequiredService<NpgsqlDataSource>();
    await using var command = db.CreateCommand(await reader.ReadToEndAsync());
    await command.ExecuteNonQueryAsync();
    Console.WriteLine("Database migration completed.");
    return;
}

app.MapGet("/health/live", () => Results.Ok(new { status = "live" }));
app.MapGet("/health/ready", async (NpgsqlDataSource db, CancellationToken ct) =>
{
    try
    {
        await using var command = db.CreateCommand("SELECT 1 FROM todos LIMIT 1");
        await command.ExecuteScalarAsync(ct);
        return Results.Ok(new { status = "ready" });
    }
    catch
    {
        return Results.StatusCode(503);
    }
});

app.MapPost("/todos", async (CreateTodo request, NpgsqlDataSource db, CancellationToken ct) =>
{
    if (!TodoRules.IsValidTitle(request.Title))
        return Results.BadRequest(new { error = "Title must contain 1 to 200 characters." });

    await using var command = db.CreateCommand(
        "INSERT INTO todos (title, is_complete) VALUES ($1, false) RETURNING id");
    command.Parameters.AddWithValue(request.Title.Trim());
    var id = (long)(await command.ExecuteScalarAsync(ct))!;
    var item = new TodoItem(id, request.Title.Trim(), false);
    return Results.Created($"/todos/{id}", item);
});

app.MapGet("/todos/{id:long}", async (long id, NpgsqlDataSource db, CancellationToken ct) =>
{
    await using var command = db.CreateCommand(
        "SELECT id, title, is_complete FROM todos WHERE id = $1");
    command.Parameters.AddWithValue(id);
    await using var reader = await command.ExecuteReaderAsync(ct);
    if (!await reader.ReadAsync(ct)) return Results.NotFound();
    var title = app.Configuration.GetValue<bool>("BEHAVIOR_REGRESSION") ? "incorrect-response" : reader.GetString(1);
    return Results.Ok(new TodoItem(reader.GetInt64(0), title, reader.GetBoolean(2)));
});

app.MapGet("/todos", async (NpgsqlDataSource db, CancellationToken ct) =>
{
    var items = new List<TodoItem>();
    await using var command = db.CreateCommand("SELECT id, title, is_complete FROM todos ORDER BY id");
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
        items.Add(new TodoItem(reader.GetInt64(0), reader.GetString(1), reader.GetBoolean(2)));
    return Results.Ok(items);
});
app.MapDelete("/todos/{id:long}", async (long id, NpgsqlDataSource db, CancellationToken ct) =>
{
    await using var command = db.CreateCommand("DELETE FROM todos WHERE id = $1");
    command.Parameters.AddWithValue(id);
    return await command.ExecuteNonQueryAsync(ct) == 1 ? Results.NoContent() : Results.NotFound();
});
app.Run();

public record CreateTodo(string Title);
public record TodoItem(long Id, string Title, bool IsComplete);
public static class TodoRules
{
    public static bool IsValidTitle(string? title) =>
        !string.IsNullOrWhiteSpace(title) && title.Trim().Length <= 200;
}

public partial class Program;
