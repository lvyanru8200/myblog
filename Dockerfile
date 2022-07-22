FROM klakegg/hugo:ext-ubuntu

EXPOSE 1313

COPY ./themes/LoveIt ./themes/LoveIt
COPY ./assets ./assets
COPY ./content ./content
COPY ./static ./static
COPY ./layouts ./layouts
COPY ./config.toml ./config.toml
COPY ./.git ./.git
CMD ["serve"]