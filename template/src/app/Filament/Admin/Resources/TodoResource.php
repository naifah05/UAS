<?php

namespace App\Filament\Resources;

use App\Filament\Resources\TodoResource\Pages;
use App\Models\Todo;
use Filament\Resources\Resource;
use Filament\Forms;
use Filament\Tables;

class TodoResource extends Resource
{
    protected static ?string $model = Todo::class;
    protected static ?string $navigationIcon = 'heroicon-o-check-circle';

    public static function form(Forms\Form $form): Forms\Form
    {
        return $form->schema([
            Forms\Components\TextInput::make('title')->required(),
            Forms\Components\Textarea::make('description'),
            Forms\Components\Toggle::make('is_done')->label('Selesai?'),
        ]);
    }

    public static function table(Tables\Table $table): Tables\Table
    {
        return $table->columns([
            Tables\Columns\TextColumn::make('title')->searchable(),
            Tables\Columns\TextColumn::make('description')->limit(30),
            Tables\Columns\IconColumn::make('is_done')->boolean(),
            Tables\Columns\TextColumn::make('created_at')->dateTime(),
        ])->filters([])->actions([Tables\Actions\EditAction::make()])->bulkActions([
            Tables\Actions\DeleteBulkAction::make(),
        ]);
    }

    public static function getPages(): array
    {
        return [
            'index' => Pages\ListTodos::route('/'),
        ];
    }
}
