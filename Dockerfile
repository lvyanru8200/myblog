FROM klakegg/hugo:ext-ubuntu

EXPOSE 1313

RUN git clone https://hub.fastgit.xyz/dillonzq/LoveIt.git ./themes/LoveIt
COPY ./assets ./assets
COPY ./content ./content
COPY ./static ./static
COPY ./layouts ./layouts
COPY ./config.toml ./config.toml
CMD ["serve"]