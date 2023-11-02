const std = @import("std");
const ArrayList = std.ArrayList;
const Arena = std.heap.ArenaAllocator;
const Random = std.rand.DefaultPrng;

const c = @cImport(@cInclude("raylib.h"));

const Obj = struct {
    pos: c.Vector2,
    size: c.Vector2,
    vel: c.Vector2,
    pub fn collide(self: *Obj, b: Obj) bool {
        return self.pos.x + self.size.x >= b.pos.x and self.pos.x <= b.pos.x + b.size.x and self.pos.y + self.size.y >= b.pos.y and self.pos.y <= b.pos.y + b.size.y;
    }
};

const State = enum {
    PLAYING,
    DEAD,
};

const Player = struct {
    obj: Obj,
    lives: i32,
    hp: i32,
    score: i32,
    pub fn reset(self: *Player) void {
        self.obj = newObj(WIDTH / 2 - self.obj.size.x / 2, HEIGHT - 30);
        self.lives = 3;
        self.hp = 3;
        self.score = 0;
    }
    pub fn isDead(self: Player) bool {
        return self.lives == 0 and self.hp - 1 == 0;
    }
    pub fn hit(self: *Player) void {
        if (self.hp - 1 == 0) {
            self.lives -= 1;
            self.hp = 3;
        } else {
            self.hp -= 1;
        }
    }
};

fn newObj(x: f32, y: f32) Obj {
    return Obj{ .pos = c.Vector2{ .x = x, .y = y }, .size = c.Vector2{ .x = 20, .y = 20 }, .vel = c.Vector2{ .x = 0, .y = 0 } };
}

fn newObjEx(x: f32, y: f32, vx: f32, vy: f32) Obj {
    return Obj{ .pos = c.Vector2{ .x = x, .y = y }, .size = c.Vector2{ .x = 20, .y = 20 }, .vel = c.Vector2{ .x = vx, .y = vy } };
}

const WIDTH: i32 = 600;
const HEIGHT: i32 = 800;

pub fn main() !void {
    var pipes = ArrayList(Obj).init(std.heap.page_allocator);
    var dirtyPipes = ArrayList(usize).init(std.heap.page_allocator);
    var bullets = ArrayList(Obj).init(std.heap.page_allocator);
    var dirtyBullets = ArrayList(usize).init(std.heap.page_allocator);

    var ship = Player{ .obj = newObj(300, 770), .lives = 3, .hp = 3, .score = 0 };

    c.InitWindow(WIDTH, HEIGHT, "Hello Zig");
    c.InitAudioDevice();
    c.SetTargetFPS(60);

    const pipeSound = c.LoadSound("./pipe.mp3");
    const laserSound = c.LoadMusicStream("./laserShoot.wav");

    defer {
        c.UnloadSound(pipeSound);
        c.UnloadMusicStream(laserSound);
        c.CloseAudioDevice();
        c.CloseWindow();
        pipes.deinit();
        bullets.deinit();
    }

    var rnd = Random.init(@as(u64, @bitCast(std.time.timestamp())));
    const time: f32 = 1.0;
    const bulletTime: f32 = 0.5;
    var pipeTimer: f32 = 0.0;
    var bulletTimer: f32 = time;

    var state = State.PLAYING;

    while (!c.WindowShouldClose()) {
        switch (state) {
            State.PLAYING => {

                //Update
                c.UpdateMusicStream(laserSound);

                if (pipeTimer < time) {
                    pipeTimer += c.GetFrameTime();
                } else {
                    try pipes.append(newObjEx(rnd.random().float(f32) * WIDTH - 30, 0, 0, rnd.random().float(f32) * 5));
                    pipeTimer = 0.0;
                }

                if (bulletTimer < bulletTime) {
                    bulletTimer += c.GetFrameTime();
                    c.StopMusicStream(laserSound);
                }

                for (pipes.items, 0..) |_, i| {
                    pipes.items[i].pos.y += pipes.items[i].vel.y;
                    if (pipes.items[i].collide(ship.obj)) {
                        if (ship.isDead()) {
                            state = State.DEAD;
                        } else {
                            ship.hit();
                            try dirtyPipes.append(i);
                        }
                    }
                    if (pipes.items[i].pos.y + pipes.items[i].size.y > HEIGHT) {
                        try dirtyPipes.append(i);
                        c.PlaySound(pipeSound);
                    }
                }

                // Update bullets
                for (bullets.items, 0..) |_, i| {
                    if (bullets.items[i].pos.y < 0) {
                        try dirtyBullets.append(i);
                        continue;
                    }
                    bullets.items[i].pos.y -= bullets.items[i].vel.y;
                    var dirty = false;
                    for (pipes.items, 0..) |_, j| {
                        if (bullets.items[i].collide(pipes.items[j])) {
                            try dirtyPipes.append(j);
                            dirty = true;
                            ship.score += 1;
                        }
                    }
                    if (dirty) try dirtyBullets.append(i);
                }

                for (dirtyPipes.items) |dirtyPipe| {
                    _ = pipes.swapRemove(dirtyPipe);
                }

                for (dirtyBullets.items) |dirtyBullet| {
                    _ = bullets.swapRemove(dirtyBullet);
                }

                dirtyPipes.clearAndFree();
                dirtyBullets.clearAndFree();

                if (c.IsKeyDown(c.KEY_A)) {
                    ship.obj.pos.x -= 5;
                    if (ship.obj.pos.x < 0) ship.obj.pos.x = 0.0;
                } else if (c.IsKeyDown(c.KEY_D)) {
                    ship.obj.pos.x += 5;
                    if (ship.obj.pos.x > WIDTH - ship.obj.size.x) ship.obj.pos.x = WIDTH - ship.obj.size.x;
                } else if (c.IsKeyPressed(c.KEY_Q)) {
                    state = State.DEAD;
                }

                // Shoot
                if (c.IsKeyDown(c.KEY_SPACE) and bulletTimer >= bulletTime) {
                    try bullets.append(newObjEx(ship.obj.pos.x, ship.obj.pos.y - 3.0, 0, 5));
                    bulletTimer = 0.0;
                    c.PlayMusicStream(laserSound);
                }

                // Render
                c.ClearBackground(c.RAYWHITE);
                c.BeginDrawing();

                // Draw Ship
                c.DrawRectangle(@intFromFloat(ship.obj.pos.x), @intFromFloat(ship.obj.pos.y), @intFromFloat(ship.obj.size.x), @intFromFloat(ship.obj.size.y), c.GREEN);

                // Draw Pipes
                for (pipes.items) |pipe| {
                    c.DrawRectangle(@intFromFloat(pipe.pos.x), @intFromFloat(pipe.pos.y), @intFromFloat(pipe.size.y), @intFromFloat(pipe.size.y), c.RED);
                }

                // Draw Bullets
                for (bullets.items) |bullet| {
                    c.DrawRectangle(@intFromFloat(bullet.pos.x), @intFromFloat(bullet.pos.y), @intFromFloat(bullet.size.y), @intFromFloat(bullet.size.y), c.BLUE);
                }

                const scoreLabel = c.TextFormat("SCORE: %d", ship.score);
                c.DrawText(scoreLabel, WIDTH / 2 - @divFloor(c.MeasureText(scoreLabel, 20), 2), 10, 20, c.BLACK);

                c.DrawText(c.TextFormat("LIVES: %d", ship.lives), 20, 20, 20, c.BLACK);
                c.DrawText(c.TextFormat("HP: %d", ship.hp), 20, 50, 20, c.BLACK);

                c.EndDrawing();
            },
            State.DEAD => {
                if (c.IsKeyPressed(c.KEY_SPACE)) {
                    pipes.clearAndFree();
                    dirtyPipes.clearAndFree();
                    bullets.clearAndFree();
                    dirtyBullets.clearAndFree();
                    ship.reset();
                    state = State.PLAYING;
                }

                c.ClearBackground(c.RED);
                c.BeginDrawing();
                const deadLabel = "YOU DEAD!";
                c.DrawText(deadLabel, WIDTH / 2 - @divFloor(c.MeasureText(deadLabel, 20), 2), HEIGHT / 2, 20, c.LIGHTGRAY);
                const scoreLabel = c.TextFormat("%d", ship.score);
                c.DrawText(scoreLabel, WIDTH / 2 - @divFloor(c.MeasureText(scoreLabel, 20), 2), HEIGHT / 2 + 30, 20, c.BLACK);
                const playAgain = "Press SPACE to start again!";
                c.DrawText(playAgain, WIDTH / 2 - @divFloor(c.MeasureText(playAgain, 20), 2), HEIGHT / 2 + 60, 20, c.BLACK);

                c.EndDrawing();
            },
        }
    }
}
